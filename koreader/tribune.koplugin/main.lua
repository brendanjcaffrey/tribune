--[[--
tribune client for koreader.

it signs in to a tribune server, keeps the token, and keeps its own picture of
the library up to date against that server.

@module koplugin.tribune
--]]--

local DataStorage = require("datastorage")
local Device = require("device")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local FileChooser = require("ui/widget/filechooser")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local JSON = require("json")
local LuaSettings = require("luasettings")
local Math = require("optmath")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local NewsletterCache = require("newslettercache")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local http = require("socket.http")
local logger = require("logger")
local ltn12 = require("ltn12")
local lfs = require("libs/libkoreader-lfs")
local socket = require("socket")
local socketutil = require("socketutil")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

-- every request is synchronous, so these timeouts are the only thing keeping a
-- server that never answers from freezing the interface for good. the block
-- timeout applies while nothing is arriving, the total timeout to the whole
-- transfer once the first chunk has arrived.
local BLOCK_TIMEOUT = 5
local TOTAL_TIMEOUT = 15

local GIGABYTE = 1024 * 1024 * 1024

-- how many rows the server puts in one page. it is the server's number, not
-- ours: a page that comes back full is the only sign that there may be more.
local PAGE_SIZE = 100
-- a runaway sync would otherwise keep asking for pages for as long as the
-- server keeps answering. this stops one sync after a hundred thousand rows,
-- which is far more library than anyone has and far less than forever.
local MAX_PAGES = 1000

-- progress is a fraction of the document between 0 and 1, quantised to four
-- decimal places. koreader's own Math.roundPercent does the quantising, and the
-- other clients copy it, so no renderer's value disagrees with another's. see
-- docs/adr/0001-progress-as-a-fraction.md.
local function isFraction(value)
    -- a nan is the only number that is not equal to itself, and an infinity is
    -- what a document of no height divides into
    return type(value) == "number" and value == value
        and value >= 0 and value <= 1
end

local function formatProgress(fraction)
    return string.format("%.4f", Math.roundPercent(fraction))
end

-- a stored value that is not a fraction means the newsletter has never been
-- opened. that is also what retires the epub cfis stored before progress became
-- a fraction: nothing migrates them, each is overwritten the first time its
-- newsletter is read on any client.
local function parseProgress(stored)
    if type(stored) ~= "string" then return nil end
    local value = tonumber(stored)
    if not isFraction(value) then return nil end
    return Math.roundPercent(value)
end

-- sync_on_return is on the module rather than on an instance. the plugin that
-- sets it is the reader's, and the one that acts on it belongs to the file
-- browser built afterwards, so an instance would not carry it across. it is
-- written as Tribune.sync_on_return, never self.sync_on_return, which would put
-- a copy on the instance and lose it again.
local Tribune = WidgetContainer:extend{
    name = "tribune",
    sync_on_return = false,
    -- the reader instantiates every plugin regardless of this flag, so all it
    -- really says is that the file browser wants us too. staying out of the
    -- reader's menu is done in init.
    is_doc_only = false,
    settings_file = DataStorage:getSettingsDir() .. "/tribune.lua",
    -- a file of its own rather than a corner of the settings. the settings file
    -- is small and rewritten whole every time the token changes; the cache is
    -- large and appended to a page at a time, and putting them together would
    -- make every sign-in rewrite the library.
    cache_file = DataStorage:getSettingsDir() .. "/tribune_newsletters.lua",
    newsletters_dir = DataStorage:getDataDir() .. "/newsletters",
    settings = nil,
    cache = nil,
}

function Tribune:init()
    self:loadSettings()
    -- file browser menu only. the reader gets no entry of its own.
    if not self.ui.document then
        self:buildSortMode()
        self:registerNewsletterActions()
        self:attachSortMode()
        self.ui.menu:registerToMainMenu(self)
        -- coming back from a newsletter is the only thing that syncs a browser
        -- as it opens, since it has a position and often a read state to send.
        -- opening the browser for any other reason has nothing new to say.
        if Tribune.sync_on_return then
            Tribune.sync_on_return = false
            self:scheduleSync(true)
        end
    end
end

--[[ file browser actions ]]--

-- a path in the library names a newsletter by its id, and nothing else in the
-- folder does. anything else -- a book the reader put there, a file browser
-- somewhere else entirely -- is not ours and gets no id.
function Tribune:newsletterIdFrom(path)
    if type(path) ~= "string" then return nil end
    return tonumber(path:match("^" .. self.newsletters_dir .. "/(%d+)%.epub$"))
end

function Tribune:registerNewsletterActions()
    if not self.ui.addFileDialogButtons then return end
    self.ui:addFileDialogButtons("tribune_newsletter_actions", function(path, is_file)
        if not is_file then return nil end
        local id = self:newsletterIdFrom(path)
        if not id then return nil end
        return {
            {
                text = _("Mark as read"),
                callback = function() self:markNewsletterRead(id) end,
            },
            {
                text = _("Mark as unread"),
                callback = function() self:markNewsletterUnread(id) end,
            },
            {
                text = _("Delete"),
                callback = function() self:deleteNewsletter(id) end,
            },
        }
    end)
end

function Tribune:markNewsletterRead(id)
    self:setNewsletterRead(id, true)
end

function Tribune:markNewsletterUnread(id)
    self:setNewsletterRead(id, false)
end

function Tribune:setNewsletterRead(id, read)
    local cache = self:getCache()
    if not cache:setRead(id, read) then return end
    cache:queueUpdate({ kind = read and "read" or "unread", id = id })
    self:refreshBrowser()
end

function Tribune:deleteNewsletter(id)
    local cache = self:getCache()
    if not cache:setDeleted(id, true) then return end
    cache:queueUpdate({ kind = "delete", id = id })
    self:refreshBrowser()
end

--[[ reading a newsletter ]]--

-- the reader's own position, as a fraction, read from the live reader. the
-- reading state on disk cannot answer this when a document closes: the reader
-- flushes it after the document has gone, so at that point it still holds the
-- previous save's values.
function Tribune:currentProgress()
    local document = self.ui and self.ui.document
    if not document then return nil end
    -- crengine and the page-based renderers each know where they are and say so
    -- the same way. either answer is a fraction of the document as laid out.
    local module = document.info and document.info.has_pages
        and self.ui.paging or self.ui.rolling
    if not module or not module.getLastPercent then return nil end
    local fraction = module:getLastPercent()
    if not isFraction(fraction) then return nil end
    return Math.roundPercent(fraction)
end

-- opening a newsletter seeks to the position the server knows about. a progress
-- still sitting in the queue has not reached the server, so in that case this
-- device holds the newer of the two and keeps the position koreader restored.
--
-- this runs after the reader modules have had the event, since they are
-- registered before any plugin, so the seek moves off a restored position
-- rather than being overwritten by one.
function Tribune:onReaderReady()
    local document = self.ui and self.ui.document
    if not document then return end
    local id = self:newsletterIdFrom(document.file)
    if not id then return end

    local cache = self:getCache()
    -- opening the file is what says it is still wanted, so this is what holds
    -- the epub on the device once the newsletter itself is finished with
    cache:touchDownload(id)

    if not cache:hasPendingUpdate(id, "progress") then
        local newsletter = cache:get(id)
        local fraction = newsletter and parseProgress(newsletter.progress)
        if fraction and fraction ~= self:currentProgress() then
            self.ui:handleEvent(Event:new("GotoPercent", fraction * 100))
        end
    end

    -- where this reading started, so that closing without having read on can be
    -- told from closing a page further along. it is taken after the seek, so an
    -- approximate landing is the mark rather than the value that was aimed at.
    self.opening_progress = self:currentProgress()
end

-- the reader has already asked whether this book was finished. its answer is
-- recorded in summary before CloseDocument, unlike the position and percentage.
function Tribune:onCloseDocument()
    local document = self.ui and self.ui.document
    local settings = self.ui and self.ui.doc_settings
    if not document or not settings then return end
    local id = self:newsletterIdFrom(document.file)
    if not id then return end
    local summary = settings:readSetting("summary")
    if summary and summary.status == "complete" then self:markNewsletterRead(id) end
    self:recordProgress(id)
    -- a position at the least, often a read state as well, for the browser
    -- this is about to return to to send.
    Tribune.sync_on_return = true
end

-- progress goes on the same queue as the other actions, so it survives being
-- offline, and one queued value per newsletter supersedes the last rather than
-- one being sent per page turn. reaching the end says nothing about whether the
-- newsletter has been read: that stays a separate, deliberate act.
function Tribune:recordProgress(id)
    local fraction = self:currentProgress()
    if not fraction or fraction == self.opening_progress then return end
    local cache = self:getCache()
    local newsletter = cache:get(id)
    if not newsletter then return end
    local progress = formatProgress(fraction)
    if newsletter.progress == progress then return end
    cache:setProgress(id, progress)
    cache:queueUpdate({ kind = "progress", id = id, progress = progress })
end

--[[ file browser sorting ]]--

-- the browser asks item_func once per visible file, then compares the decorated
-- items many times. keeping the cache lookup here makes sorting a folder cheap.
--
-- the mode is deliberately not added to FileChooser.collates. a mode in that
-- table is a mode in every browser's Sort by menu, and the browser remembers
-- the chosen one by name in its own settings. it reads that name while it is
-- being built, which happens before any plugin has been loaded, and a name it
-- cannot find there it quietly replaces with sort by name -- so a mode that
-- exists only while the plugin does loses the reader's choice every time the
-- browser is rebuilt. out of the table there is no choice to lose, and no
-- folder but the library can be ordered this way.
function Tribune:buildSortMode()
    local cache = self:getCache()
    self.sort_mode = {
        text = _("unread first"),
        item_func = function(item)
            local id = tonumber(item.path:match("/(%d+)%.epub$"))
            local newsletter = id and cache:get(id)
            if newsletter and not newsletter.deleted then
                item.text = newsletter.title ~= "" and newsletter.title or item.text:gsub("%.epub$", "")
                item.tribune_newsletter = {
                    id = id,
                    created_at = newsletter.created_at,
                    read = newsletter.read,
                }
            end
        end,
        init_sort_func = function()
            return function(a, b)
                local left = a.tribune_newsletter
                local right = b.tribune_newsletter
                if not left or not right then return a.text < b.text end
                if left.read ~= right.read then return not left.read end
                if left.created_at ~= right.created_at then
                    return left.created_at > right.created_at
                end
                return left.id > right.id
            end
        end,
        mandatory_func = function(item)
            local newsletter = item.tribune_newsletter
            if newsletter then
                local date = newsletter.created_at:sub(1, 10)
                if newsletter.read then
                    item.dim = true
                    return "✓ " .. date
                end
                return date
            end
            return util.getFriendlySize(item.attr.size or 0)
        end,
    }
end

-- the browser resolves every path it is given, so the library's own path has to
-- be resolved before the two can be compared. on a device that reaches its
-- storage through a symlink the unresolved strings never match, and the library
-- folder quietly sorts like any other.
function Tribune:isLibraryPath(path)
    if type(path) ~= "string" then return false end
    if path == self.newsletters_dir then return true end
    local resolved = ffiUtil.realpath(self.newsletters_dir)
    return resolved ~= nil and path == resolved
end

-- the override goes on the class every browser is built from, not on the
-- browser in front of us. android rebuilds the file browser from scratch every
-- time the window changes shape -- a rotation, or the system resizing the app --
-- and it does so without running the file manager's init, so no plugin hears
-- about it and the browser that was patched is already gone. the class is the
-- one place a rebuild cannot drop.
function Tribune:attachSortMode()
    if FileChooser.getCollate == self.get_collate_override then return end
    self.original_get_collate = FileChooser.getCollate
    self.get_collate_override = function(chooser)
        if self:isLibraryPath(chooser.path) then
            return self.sort_mode, "tribune_unread_first"
        end
        return self.original_get_collate(chooser)
    end
    FileChooser.getCollate = self.get_collate_override
    -- a browser already listing the library was built before the override and
    -- is showing an ordinary ordering. one built afterwards never is.
    local browser = self.ui and self.ui.file_chooser
    if browser and browser.refreshPath and self:isLibraryPath(browser.path) then
        browser:refreshPath()
    end
end

function Tribune:onCloseWidget()
    if self.ui and self.ui.removeFileDialogButtons then
        self.ui:removeFileDialogButtons("tribune_newsletter_actions")
    end
    if FileChooser.getCollate == self.get_collate_override then
        FileChooser.getCollate = self.original_get_collate
    end
end

function Tribune:refreshBrowser()
    local browser = self.ui and self.ui.file_chooser
    if browser then browser:refreshPath() end
end

--[[ settings ]]--

-- a settings file of our own rather than a corner of G_reader_settings: the
-- token and the address belong together, they are ours alone, and keeping them
-- out of the global settings means they are gone with the plugin. this is what
-- opds, wallabag and cloud storage all do.
function Tribune:loadSettings()
    if self.settings then return end
    self.settings = LuaSettings:open(self.settings_file)
end

-- opened on demand rather than in init. a new file browser builds a new plugin,
-- so opening the cache in init would read and parse the whole library every
-- time a book is closed, for nothing.
function Tribune:getCache()
    if not self.cache then
        self.cache = NewsletterCache:open(self.cache_file)
    end
    return self.cache
end

function Tribune:getNewslettersDir()
    if lfs.attributes(self.newsletters_dir, "mode") ~= "directory" then
        local ok, err = lfs.mkdir(self.newsletters_dir)
        if not ok then
            logger.err("tribune: could not create newsletters directory:", tostring(err))
            return nil
        end
    end
    return self.newsletters_dir
end

function Tribune:getServerAddress()
    local address = self.settings:readSetting("server_address")
    if address == "" then return nil end
    return address
end

function Tribune:getToken()
    return self.settings:readSetting("token")
end

function Tribune:getUsername()
    return self.settings:readSetting("username")
end

-- written out straight away rather than on the flush settings event, because a
-- reader is more often killed than closed and the sign-in has to survive that.
function Tribune:setSession(token, username)
    self.settings:saveSetting("token", token)
    self.settings:saveSetting("username", username)
    self.settings:flush()
end

-- the token is what signing out discards. the username stays behind as the
-- prefill for the next sign-in, and means nothing on its own.
function Tribune:clearSession()
    self.settings:delSetting("token")
    self.settings:flush()
end

--[[ menu ]]--

function Tribune:addToMainMenu(menu_items)
    menu_items.tribune = {
        text = _("Tribune"),
        -- "tools" is a real id in the file browser's menu order table, see
        -- frontend/ui/elements/filemanager_menu_order.lua. a hint that names
        -- nothing crashes menu generation outright, so it is checked rather
        -- than guessed at.
        sorting_hint = "tools",
        sub_item_table = {
            {
                text_func = function()
                    return self:accountText()
                end,
                help_text = _("Tap to ask the server who this device is signed in as."),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:checkAccount(touchmenu_instance)
                end,
            },
            {
                text_func = function()
                    return self:getToken() and _("Sign out") or _("Sign in")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    if self:getToken() then
                        self:signOut(touchmenu_instance)
                    else
                        self:signIn(touchmenu_instance)
                    end
                end,
                separator = true,
            },
            {
                text = _("Sync now"),
                help_text = _("Fetch everything that has changed on the server since the last sync."),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:syncNow(touchmenu_instance)
                end,
            },
            {
                text_func = function()
                    return self:libraryText()
                end,
                help_text = _("Open the downloaded newsletters."),
                callback = function() self:openLibrary() end,
                separator = true,
            },
            {
                text_func = function()
                    local address = self:getServerAddress()
                    return address and T(_("Server address: %1"), address)
                        or _("Server address: not set")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:editServerAddress(touchmenu_instance)
                end,
            },
        },
    }
end

function Tribune:accountText()
    if not self:getToken() then
        return _("Not signed in")
    end
    local username = self:getUsername()
    if username then
        return T(_("Signed in as %1"), username)
    end
    return _("Signed in")
end

--[[ requests ]]--

-- one synchronous request, returning ok, result, code. result is the decoded
-- json when ok, and a message to show the reader when not.
--
-- synchronous is deliberate. the kindle reaches the server through koreader's
-- own http proxy setting, which assigns luasocket's http.PROXY, and only
-- socket.http requests honour it. see
-- docs/adr/0002-plain-http-for-the-kindle.md.
function Tribune:request(method, path, form_body, token, expect_json)
    local address = self:getServerAddress()
    if not address then
        return false, _("No server address is set."), nil
    end

    -- the sink reads the total timeout as it is built, so the timeouts go first
    socketutil:set_timeout(BLOCK_TIMEOUT, TOTAL_TIMEOUT)
    local sink = {}
    local request = {
        url = address .. path,
        method = method,
        headers = {},
        sink = socketutil.table_sink(sink),
    }
    if form_body then
        request.source = ltn12.source.string(form_body)
        request.headers["Content-Type"] = "application/x-www-form-urlencoded"
        request.headers["Content-Length"] = tostring(#form_body)
    end
    if token then
        request.headers["Authorization"] = "Bearer " .. token
    end

    logger.dbg("tribune: request", method, request.url)
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    -- no headers means luasocket returned nil and an error rather than a
    -- response, so what we have in code is that error
    if headers == nil then
        logger.err("tribune: request failed:", tostring(status or code))
        return false, T(_("Could not reach the server: %1"), tostring(status or code)), nil
    end

    if code ~= 200 then
        logger.err("tribune: request returned", tostring(status or code))
        return false, T(_("The server refused the request: %1"), tostring(status or code)), code
    end

    if expect_json == false then return true, nil, code end

    local content = table.concat(sink)
    local ok, parsed = pcall(JSON.decode, content)
    if not ok or type(parsed) ~= "table" then
        logger.err("tribune: response was not json:", content)
        return false, _("The server's answer could not be read."), code
    end
    return true, parsed, code
end

-- streams an epub into a temporary file. keeping response bytes out of memory
-- matters on older devices, and renaming only after a complete 200 response
-- means a failed transfer cannot replace a readable book with a partial one.
function Tribune:download(path, destination)
    local address = self:getServerAddress()
    if not address then return false, _("No server address is set."), nil end

    local partial = destination .. ".partial"
    os.remove(partial)
    local output, open_error = io.open(partial, "wb")
    if not output then
        return false, T(_("Could not write the epub: %1"), tostring(open_error)), nil
    end

    socketutil:set_timeout(BLOCK_TIMEOUT, TOTAL_TIMEOUT)
    local write_error
    local request = {
        url = address .. path,
        method = "GET",
        headers = { ["Authorization"] = "Bearer " .. self:getToken() },
        sink = function(chunk, err)
            if chunk then
                local ok, problem = output:write(chunk)
                if not ok then write_error = problem end
            end
            return write_error and nil or 1, err
        end,
    }
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    output:close()

    if headers == nil then
        os.remove(partial)
        return false, T(_("Could not reach the server: %1"), tostring(status or code)), nil
    end
    if write_error then
        os.remove(partial)
        return false, T(_("Could not write the epub: %1"), tostring(write_error)), code
    end
    if code ~= 200 then
        os.remove(partial)
        return false, T(_("The server refused the epub download: %1"), tostring(status or code)), code
    end
    if not os.rename(partial, destination) then
        os.remove(partial)
        return false, _("Could not put the epub in the library."), code
    end
    return true, nil, code
end

-- the interface cannot repaint while a synchronous request is in flight, so the
-- message has to be on screen before the request starts. it has no timeout, so
-- a request that takes its full fifteen seconds shows what it is waiting for
-- and can be tapped away afterwards rather than looking like a freeze.
function Tribune:withProgress(text, action)
    local info = InfoMessage:new{ text = text }
    UIManager:show(info)
    UIManager:forceRePaint()
    -- android kills an app that ignores input for too long. no-op elsewhere.
    Device:setIgnoreInput(true)
    local called, ok, result, code = pcall(action)
    Device:setIgnoreInput(false)
    UIManager:close(info)
    if not called then
        logger.err("tribune: request raised:", tostring(ok))
        return false, _("Something went wrong talking to the server."), nil
    end
    return ok, result, code
end

--[[ syncing the library ]]--

-- a first sync has no cursor, so it starts from a mark that sits below every
-- row there can be and walks up from there, which is the same walk every other
-- sync does rather than a second way of doing it. the server rejects a cursor
-- id of zero, so the id is one; the timestamp is the epoch, and a row cannot
-- have that one, since the column is set to the moment the row was written.
local BEGINNING = { updated_at = "1970-01-01 00:00:00+00", id = 1 }

local function cursorQuery(direction, mark)
    return "?" .. direction .. "_timestamp=" .. util.urlEncode(mark.updated_at)
        .. "&" .. direction .. "_id=" .. tostring(mark.id)
end

local function markOf(row)
    return { updated_at = row.updated_at, id = tonumber(row.id) }
end

-- one page of the library, in the order the server sent it: after pages arrive
-- oldest change first. returns the rows, or nil and a message to show the
-- reader.
function Tribune:fetchPage(query)
    local ok, result, code = self:request("GET", "/newsletters" .. query, nil, self:getToken())
    if not ok then
        return nil, result, code
    end
    if type(result.result) ~= "table" then
        return nil, _("The server's answer could not be read."), code
    end
    return result.result
end

function Tribune:sendPendingUpdates()
    local cache = self:getCache()
    cache:expirePendingUpdates()
    while true do
        local update = cache:pendingUpdates()[1]
        if not update then break end
        local method = update.kind == "delete" and "DELETE" or "PUT"
        local path = "/newsletters/" .. update.id
        if update.kind ~= "delete" then path = path .. "/" .. update.kind end
        -- progress is the only one of these that carries a value; the rest say
        -- everything they have to say in the route
        local body = update.kind == "progress"
            and ("progress=" .. util.urlEncode(update.progress)) or nil
        local ok, message, code = self:request(method, path,
            body, self:getToken(), false)
        if not ok then return false, message, code end
        cache:removePendingUpdate(update)
    end
    return true
end

--[[--
Brings the cache up to date with the server.

A sync walks upwards. It asks for everything after the cursor and the server
answers with the hundred rows immediately above it, oldest first, so the last
row of a page is both the newest thing the plugin now knows about and the mark
the next page starts from. The walk ends at the first page that comes back
short, since a full page is the only sign that there may be more.

The cursor moves at the end of every page rather than at the end of the sync.
That is safe because the walk only ever goes one way: by the time the cursor is
moved to the last row of a page, every row at or below it has been stored. It is
also what makes an interruption cheap — the next sync starts at the last page
that finished and repeats at most the page that was in flight. Nothing is
stepped over that has not been written down first.

@treturn boolean whether it worked
@treturn table|string a summary when it worked, a message to show when it did not
--]]
function Tribune:sync()
    local token = self:getToken()
    if not token then
        return false, _("Nobody is signed in.")
    end

    local cache = self:getCache()
    -- before the updates rather than after: a newsletter whose read or deleted
    -- state is still queued keeps its file, and that is only worth checking
    -- while the queue still has it in. it also frees whatever space the
    -- finished newsletters were taking before anything new is fetched.
    local removed = self:evictDownloads()

    local updates_ok, updates_message, updates_code = self:sendPendingUpdates()
    if not updates_ok then return false, updates_message, updates_code end
    -- everything at or below the mark is already known
    local mark = cache:getCursor() or BEGINNING
    local fetched, stored = 0, 0

    for _ = 1, MAX_PAGES do
        local rows, message, code = self:fetchPage(cursorQuery("after", mark))
        if not rows then return false, message, code end
        fetched = fetched + #rows
        for _, row in ipairs(rows) do
            if cache:put(row) then stored = stored + 1 end
        end
        if #rows > 0 then
            mark = markOf(rows[#rows])
            cache:setCursor(mark.updated_at, mark.id)
        end
        if #rows < PAGE_SIZE then
            cache:setLastSync(os.time())
            cache:compactIfNeeded()
            local download_ok, downloaded, download_code = self:downloadUnread()
            if not download_ok then return false, downloaded, download_code end
            self:refreshBrowser()
            return true, {
                fetched = fetched,
                stored = stored,
                downloaded = downloaded,
                removed = removed,
            }
        end
    end

    -- more pages than anyone should have. what has been stored is kept and so
    -- is the cursor, so trying again carries on from here rather than starting
    -- at the bottom of the library again.
    logger.warn("tribune: gave up after", MAX_PAGES, "pages")
    return false, _("The library was too big to sync in one go. Try again.")
end

-- downloads the unread library from oldest to newest. a cache entry changes
-- only after its file has been renamed into place, so cancelling or a failed
-- transfer leaves the next run with an honest, usable cache.
function Tribune:downloadUnread()
    local directory = self:getNewslettersDir()
    if not directory then return false, _("Could not create the Tribune library.") end

    local disk_usage = util.diskUsage(directory)
    local free_space = disk_usage and disk_usage.available
    if free_space and free_space < GIGABYTE then
        return false, _("Tribune stopped downloading: less than 1 GB is free."), nil
    end

    local cache = self:getCache()
    local downloaded = 0
    for _, newsletter in ipairs(cache:downloads()) do
        local filename = directory .. "/" .. newsletter.id .. ".epub"
        local ok, message, code = self:download("/newsletters/" .. newsletter.id .. "/epub", filename)
        if not ok then return false, message, code end
        local previous = cache:get(newsletter.id)
        if previous and previous.downloaded_epub_updated_at then
            DocSettings:open(filename):purge(nil, { doc_settings = true })
        end
        cache:setDownloaded(newsletter.id, cache:get(newsletter.id).epub_updated_at)
        downloaded = downloaded + 1
    end
    return true, downloaded
end

-- removes the epubs the cache says are done with. the file goes with its
-- reading sidecar, since the sidecar describes a file that is no longer there
-- and would otherwise be restored over a later download of the same newsletter.
--
-- the cache entry is cleared last, so being interrupted leaves a newsletter the
-- cache still believes is downloaded and the next run removes again. removing a
-- file that has already gone costs nothing; forgetting one that is still there
-- would leave it behind for good.
function Tribune:evictDownloads(now)
    local cache = self:getCache()
    cache:startDownloadClocks(now)
    local removed = 0
    for _, id in ipairs(cache:evictions(now)) do
        local filename = self.newsletters_dir .. "/" .. id .. ".epub"
        os.remove(filename)
        DocSettings:open(filename):purge(nil, { doc_settings = true })
        cache:clearDownloaded(id)
        removed = removed + 1
    end
    if removed > 0 then logger.dbg("tribune: removed", removed, "epubs") end
    return removed
end

--[[ when syncing happens ]]--

-- a sync in the background, for the moments worth one: tapping "library", and
-- coming back from a newsletter. there is no interval between them, because
-- neither happens often enough to need one.
function Tribune:scheduleSync(quiet)
    if not self:getToken() or not self:getServerAddress() then return end
    -- two ticks, not one. koreader runs the tick queue before it repaints, so a
    -- task scheduled for the next tick would block the browser's first paint;
    -- the tick after that runs once it is on screen.
    UIManager:tickAfterNext(function()
        self:autoSync(quiet)
    end)
end

-- quiet says nobody asked for this sync: it came of closing a book rather than
-- of the reader tapping something, so being offline is not worth a message.
function Tribune:autoSync(quiet)
    -- neither of these prompts, brings the network up, or costs anything: one
    -- reads the radio's state and the other asks the interface for its address.
    -- NetworkMgr:isOnline() would be the stronger test, but it makes it by
    -- resolving a hostname, and a kindle reaching the server through koreader's
    -- proxy has no dns of its own to do that with -- see
    -- docs/adr/0002-plain-http-for-the-kindle.md.
    if not NetworkMgr:isWifiOn() or not NetworkMgr:isConnected() then
        logger.dbg("tribune: offline, not syncing")
        if not quiet then
            UIManager:show(InfoMessage:new{
                text = _("Tribune did not sync: this device is offline."),
                timeout = 2,
            })
        end
        return
    end

    local ok, result, code = self:sync()
    if ok then
        logger.dbg("tribune: synced", result.fetched, "rows,", result.stored,
                   "kept,", result.removed, "epubs removed")
        return
    end
    if code == 401 then
        -- the token is no longer any good, and no amount of retrying will fix
        -- it, so say so once rather than failing quietly every time
        self:clearSession()
        UIManager:show(InfoMessage:new{
            text = _("This device is no longer signed in. Sign in again."),
        })
        return
    end
    -- worth saying, but not worth standing in the way of the browser
    UIManager:show(InfoMessage:new{ text = result, timeout = 3 })
end

-- asked for explicitly, so this one is allowed to bring the network up.
--
-- willRerunWhenConnected rather than willRerunWhenOnline: the online test is a
-- dns lookup against a public host, and the server lives on a tailnet the
-- kindle reaches through a proxy. having an address on the network is what
-- actually has to be true before the request is worth making.
function Tribune:syncNow(touchmenu_instance)
    if not self:getServerAddress() then
        UIManager:show(InfoMessage:new{ text = _("Set the Tribune server address first.") })
        return
    end
    if not self:getToken() then
        UIManager:show(InfoMessage:new{ text = _("Nobody is signed in.") })
        return
    end
    if NetworkMgr:willRerunWhenConnected(function() self:syncNow(touchmenu_instance) end) then
        return
    end

    local ok, result, code = self:withProgress(_("Syncing with Tribune…"), function()
        return self:sync()
    end)

    if not ok then
        if code == 401 then
            self:clearSession()
            UIManager:show(InfoMessage:new{
                text = _("This device is no longer signed in. Sign in again."),
            })
        else
            UIManager:show(InfoMessage:new{ text = result })
        end
    else
        local total, unread = self:getCache():counts()
        UIManager:show(InfoMessage:new{
            text = T(_("Synced. %1 newsletters, %2 unread."), total, unread),
        })
    end

    if touchmenu_instance then
        touchmenu_instance:updateItems()
    end
end

function Tribune:libraryText()
    local cache = self:getCache()
    local total, unread = cache:counts()
    local last = cache:getLastSync()
    if not last then
        return T(_("Library: %1 unread — never synced"), unread)
    end
    return T(_("Library: %1 unread — last synced %2"), unread,
             os.date("%Y-%m-%d %H:%M", last))
end

function Tribune:openLibrary()
    local directory = self:getNewslettersDir()
    local browser = self.ui and self.ui.file_chooser
    if directory and browser then browser:changeToPath(directory) end
    -- looking at the library is a moment for it to be up to date. this one is
    -- on wifi only and does not prompt; "sync now" is the one that insists.
    self:scheduleSync()
end

--[[ signing in and out ]]--

function Tribune:signIn(touchmenu_instance)
    if not self:getServerAddress() then
        UIManager:show(InfoMessage:new{
            text = _("Set the Tribune server address first."),
        })
        return
    end
    if NetworkMgr:willRerunWhenOnline(function() self:signIn(touchmenu_instance) end) then
        return
    end

    local dialog
    dialog = MultiInputDialog:new{
        title = _("Sign in to Tribune"),
        fields = {
            {
                text = self:getUsername(),
                hint = _("username"),
            },
            {
                hint = _("password"),
                text_type = "password",
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Sign in"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        local username = util.trim(fields[1] or "")
                        local password = fields[2] or ""
                        if username == "" or password == "" then
                            UIManager:show(InfoMessage:new{
                                text = _("A username and a password are both needed."),
                                timeout = 2,
                            })
                            return
                        end
                        UIManager:close(dialog)
                        -- let the dialog and its keyboard get off the screen
                        -- before the request blocks everything
                        UIManager:nextTick(function()
                            self:doSignIn(username, password, touchmenu_instance)
                        end)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Tribune:doSignIn(username, password, touchmenu_instance)
    -- the server hashes the password itself, so it goes over as it was typed
    local body = "username=" .. util.urlEncode(username)
        .. "&password=" .. util.urlEncode(password)

    -- both requests share one message: the token is worth nothing until we know
    -- whose it is
    local ok, result, code = self:withProgress(_("Signing in…"), function()
        local auth_ok, auth_result, auth_code = self:request("POST", "/auth", body)
        if not auth_ok then
            return auth_ok, auth_result, auth_code
        end
        local token = auth_result.jwt
        if type(token) ~= "string" or token == "" then
            return false, _("The server did not send a token."), auth_code
        end
        local who_ok, who = self:request("GET", "/auth", nil, token)
        return true, { token = token, username = who_ok and who.username or nil }, auth_code
    end)

    if not ok then
        local message = result
        if code == 401 then
            message = _("That username and password were not accepted.")
        end
        UIManager:show(InfoMessage:new{ text = message })
        return
    end

    self:setSession(result.token, result.username or username)
    if touchmenu_instance then
        touchmenu_instance:updateItems()
    end
    UIManager:show(InfoMessage:new{
        text = T(_("Signed in as %1."), self:getUsername()),
    })
end

function Tribune:signOut(touchmenu_instance)
    self:clearSession()
    self:removeDownloadedNewsletters()
    self:getCache():reset()
    self:refreshBrowser()
    if touchmenu_instance then
        touchmenu_instance:updateItems()
    end
    UIManager:show(InfoMessage:new{ text = _("Signed out.") })
end

function Tribune:removeDownloadedNewsletters()
    for id in pairs(self:getCache():all()) do
        local filename = self.newsletters_dir .. "/" .. id .. ".epub"
        os.remove(filename)
        DocSettings:open(filename):purge(nil, { doc_settings = true })
    end
end

function Tribune:checkAccount(touchmenu_instance)
    local token = self:getToken()
    if not token then
        UIManager:show(InfoMessage:new{ text = _("Nobody is signed in.") })
        return
    end
    if NetworkMgr:willRerunWhenOnline(function() self:checkAccount(touchmenu_instance) end) then
        return
    end

    local ok, result, code = self:withProgress(_("Asking the server…"), function()
        return self:request("GET", "/auth", nil, token)
    end)

    if ok then
        self:setSession(token, result.username)
        UIManager:show(InfoMessage:new{
            text = T(_("Signed in as %1."), tostring(result.username)),
        })
    elseif code == 401 then
        self:clearSession()
        UIManager:show(InfoMessage:new{
            text = _("This device is no longer signed in. Sign in again."),
        })
    else
        UIManager:show(InfoMessage:new{ text = result })
    end

    if touchmenu_instance then
        touchmenu_instance:updateItems()
    end
end

--[[ server address ]]--

function Tribune:editServerAddress(touchmenu_instance)
    local dialog
    dialog = InputDialog:new{
        title = _("Tribune server address"),
        -- the two devices reach the server differently: a tablet on a full
        -- tunnel uses the https address, a kindle in userspace networking mode
        -- uses the plain http one through koreader's own proxy setting.
        description = _("The address this device reaches the server on, with its scheme and port."),
        input = self:getServerAddress() or "https://",
        input_hint = "https://host.tailnet.ts.net:1847",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local address = util.trim(dialog:getInputText() or "")
                        address = address:gsub("/+$", "")
                        if address ~= "" and not address:match("^https?://") then
                            UIManager:show(InfoMessage:new{
                                text = _("The address has to start with http:// or https://."),
                                timeout = 2,
                            })
                            return
                        end
                        UIManager:close(dialog)
                        self:setServerAddress(address)
                        if touchmenu_instance then
                            touchmenu_instance:updateItems()
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- a token belongs to the server that issued it, so pointing the plugin at a
-- different one signs this device out. so do the ids in the cache, so the cache
-- goes with it.
function Tribune:setServerAddress(address)
    local previous = self:getServerAddress()
    if address == "" then
        self.settings:delSetting("server_address")
    else
        self.settings:saveSetting("server_address", address)
    end
    if previous ~= self:getServerAddress() then
        self.settings:delSetting("token")
        self:getCache():reset()
    end
    self.settings:flush()
end

return Tribune
