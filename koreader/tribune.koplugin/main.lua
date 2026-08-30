--[[--
tribune client for koreader.

it signs in to a tribune server, keeps the token, and keeps its own picture of
the library up to date against that server.

@module koplugin.tribune
--]]--

local DataStorage = require("datastorage")
local Device = require("device")
local DocSettings = require("docsettings")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local JSON = require("json")
local LuaSettings = require("luasettings")
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
-- opening the file browser syncs, but coming back to it from a book opens it
-- again, and a sync every time a book is closed is not what "when the file
-- browser is opened" means. so an automatic sync waits this long between goes.
local AUTO_SYNC_INTERVAL = 5 * 60

-- module scope on purpose. closing a book destroys the file browser and builds
-- a new one, plugins and all, so anything remembered on self is forgotten every
-- time a book is closed. this is remembered for as long as koreader is running.
local last_auto_sync = nil

local Tribune = WidgetContainer:extend{
    name = "tribune",
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
        self.ui.menu:registerToMainMenu(self)
        self:scheduleAutoSync()
    end
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
                help_text = _("What the plugin knows about the library, without asking the server."),
                keep_menu_open = true,
                -- nothing to do but say it again with today's numbers
                callback = function(touchmenu_instance)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
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
function Tribune:request(method, path, form_body, token)
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
            return true, { fetched = fetched, stored = stored, downloaded = downloaded }
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

--[[ when syncing happens ]]--

-- a new file browser means a new plugin, so this runs every time the browser is
-- opened -- including on the way back from a book.
function Tribune:scheduleAutoSync()
    if not self:getToken() or not self:getServerAddress() then return end
    local now = os.time()
    if last_auto_sync and now - last_auto_sync < AUTO_SYNC_INTERVAL then return end
    last_auto_sync = now

    -- two ticks, not one. koreader runs the tick queue before it repaints, so a
    -- task scheduled for the next tick would block the browser's first paint;
    -- the tick after that runs once it is on screen.
    UIManager:tickAfterNext(function()
        self:autoSync()
    end)
end

function Tribune:autoSync()
    -- neither of these prompts, brings the network up, or costs anything: one
    -- reads the radio's state and the other asks the interface for its address.
    -- NetworkMgr:isOnline() would be the stronger test, but it makes it by
    -- resolving a hostname, and a kindle reaching the server through koreader's
    -- proxy has no dns of its own to do that with -- see
    -- docs/adr/0002-plain-http-for-the-kindle.md.
    if not NetworkMgr:isWifiOn() or not NetworkMgr:isConnected() then
        logger.dbg("tribune: offline, not syncing")
        UIManager:show(InfoMessage:new{
            text = _("Tribune did not sync: this device is offline."),
            timeout = 2,
        })
        return
    end

    local ok, result, code = self:sync()
    if ok then
        logger.dbg("tribune: synced", result.fetched, "rows,", result.stored, "kept")
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
    last_auto_sync = os.time()

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
    self:getCache():reset()
    if touchmenu_instance then
        touchmenu_instance:updateItems()
    end
    UIManager:show(InfoMessage:new{ text = _("Signed out.") })
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
