local source_dir = "koreader/tribune.koplugin/"
package.path = source_dir .. "?.lua;" .. package.path

local failures = 0

local function fail(message)
    error(message, 2)
end

local function assert_equal(actual, expected)
    if actual ~= expected then
        fail("expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assert_true(value)
    if not value then fail("expected true, got " .. tostring(value)) end
end

local function test(name, action)
    local ok, problem = pcall(action)
    if ok then
        io.write("ok - " .. name .. "\n")
    else
        failures = failures + 1
        io.write("not ok - " .. name .. ": " .. tostring(problem) .. "\n")
    end
end

local stored_settings = {}
local directories = { ["/library"] = true }
-- what ffiUtil.realpath answers. empty by default, which is what a path with no
-- symlink in it looks like: the browser is handed the path it already had.
local resolved_paths = {}
local files = {}
local purged = {}
local messages = {}
local closed = {}
local free_space
local http_response
local network = {}
local clock
local scheduled = {}
-- assigned once main.lua is loaded. what the reader left behind on closing a
-- newsletter outlives the plugin that saw it, so each test starts from nothing.
local reset_plugin = function() end

local function reset_environment()
    stored_settings = {}
    directories = { ["/library"] = true }
    resolved_paths = {}
    files = {}
    purged = {}
    messages = {}
    closed = {}
    free_space = nil
    http_response = nil
    clock = nil
    scheduled = {}
    reset_plugin()
    network = { wifi_on = false, connected = false, rerun_when_connected = false }
end

package.preload["luadata"] = function()
    return {
        open = function(path)
            stored_settings[path] = stored_settings[path] or {}
            local data = stored_settings[path]
            return {
                data = data,
                max_backups = 0,
                readSetting = function(self, key) return self.data[key] end,
                saveSetting = function(self, key, value) self.data[key] = value end,
            }
        end,
    }
end

package.preload["dump"] = function() return function() return "{}" end end
package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(path, attribute)
            if attribute == "mode" and directories[path] then return "directory" end
            if attribute == "size" and files[path] then return #files[path] end
        end,
        mkdir = function(path) directories[path] = true; return true end,
    }
end
package.preload["logger"] = function() return { dbg = function() end, err = function() end, warn = function() end } end
package.preload["datastorage"] = function()
    return {
        getDataDir = function() return "/library" end,
        getSettingsDir = function() return "/settings" end,
    }
end
package.preload["device"] = function() return { setIgnoreInput = function() end } end
package.preload["docsettings"] = function()
    return { open = function(_, path)
        return { purge = function() purged[#purged + 1] = path end }
    end }
end
package.preload["ui/widget/infomessage"] = function() return { new = function(_, item) return item end } end
package.preload["ui/widget/inputdialog"] = function() return { new = function(_, item) return item end } end
package.preload["ui/widget/multiinputdialog"] = function() return { new = function(_, item) return item end } end
package.preload["ui/network/manager"] = function()
    return {
        isWifiOn = function() return network.wifi_on end,
        isConnected = function() return network.connected end,
        willRerunWhenConnected = function(_, callback)
            network.callback = callback
            return network.rerun_when_connected
        end,
    }
end
package.preload["json"] = function() return { decode = function(value) return value end } end
package.preload["optmath"] = function()
    return { roundPercent = function(percent) return math.floor(percent * 10000) / 10000 end }
end
package.preload["ui/event"] = function()
    return { new = function(_, name, ...) return { handler = "on" .. name, args = { ... } } end }
end
package.preload["luasettings"] = function() return { open = function() return {} end } end
package.preload["ui/uimanager"] = function()
    return { show = function(_, message) messages[#messages + 1] = message end,
             close = function(_, widget) closed[#closed + 1] = widget end,
             forceRePaint = function() end, nextTick = function() end,
             tickAfterNext = function(_, callback) scheduled[#scheduled + 1] = callback end }
end
package.preload["ui/widget/container/widgetcontainer"] = function()
    local widget = {}
    function widget:extend(item)
        item.__index = item
        return setmetatable(item, { __index = self })
    end
    return widget
end
package.preload["ui/widget/filechooser"] = function()
    local FileChooser = { collates = {
        strcoll = {
            text = "name",
            init_sort_func = function()
                return function(a, b) return a.text < b.text end
            end,
        },
    } }
    function FileChooser:getCollate()
        local collate = self.collates[self.selected_collate]
        if collate then return collate, self.selected_collate end
        return self.collates.strcoll, "strcoll"
    end
    return FileChooser
end
package.preload["ffi/util"] = function()
    return {
        template = function(format, value) return format:gsub("%%1", tostring(value)) end,
        realpath = function(path) return resolved_paths[path] end,
    }
end
package.preload["socket.http"] = function()
    return { request = function(request)
        return http_response(request)
    end }
end
package.preload["ltn12"] = function() return { source = { string = function() end } } end
package.preload["socket"] = function()
    return { skip = function(count, ...) return select(count + 1, ...) end }
end
package.preload["socketutil"] = function()
    return {
        set_timeout = function() end,
        reset_timeout = function() end,
        table_sink = function(output)
            return function(chunk)
                if chunk then output[#output + 1] = chunk end
                return 1
            end
        end,
    }
end
package.preload["util"] = function()
    return {
        urlEncode = function(value) return value end,
        diskUsage = function() return free_space and { available = free_space } or nil end,
        trim = function(value) return value end,
    }
end
package.preload["gettext"] = function() return function(value) return value end end

local original_open = io.open
local original_remove = os.remove
local original_rename = os.rename
local original_time = os.time
-- the clock the plugin reads. a test that cares how old a file is sets it; the
-- rest are left on the real one.
os.time = function() return clock or original_time() end
io.open = function(path, mode)
    if mode ~= "wb" then return original_open(path, mode) end
    local chunks = {}
    return {
        write = function(_, chunk) chunks[#chunks + 1] = chunk; return true end,
        close = function() files[path] = table.concat(chunks); return true end,
    }
end
os.remove = function(path)
    files[path] = nil
    stored_settings[path] = nil
    return true
end
os.rename = function(from, to)
    if not files[from] then return nil end
    files[to] = files[from]
    files[from] = nil
    return true
end

local Cache = dofile(source_dir .. "newslettercache.lua")
package.loaded["newslettercache"] = Cache
local Tribune = require("main")

reset_plugin = function()
    Tribune.sync_on_return = false
end

local function cache()
    return Cache:open("/settings/cache.lua")
end

local function tribune(with_cache)
    local instance = setmetatable({
        newsletters_dir = "/library/newsletters",
        cache = with_cache or cache(),
        getToken = function() return "token" end,
        getServerAddress = function() return "http://tribune.test" end,
    }, { __index = Tribune })
    return instance
end

-- a browser the way the file manager builds them: it owns a path and nothing
-- else, and reaches getCollate through the class. one built after the plugin
-- started is exactly what android's rebuild-on-rotate hands it.
local function browser_at(path)
    local FileChooser = require("ui/widget/filechooser")
    return setmetatable({ path = path }, { __index = FileChooser })
end

-- the sort mode is registered nowhere the browser can find on its own, so the
-- only way to reach it is a browser sitting in the library folder.
local function sort_mode_of(instance)
    return (browser_at(instance.newsletters_dir):getCollate())
end

local function row(id, fields)
    fields = fields or {}
    return {
        id = id,
        title = fields.title or "",
        created_at = fields.created_at or string.format("2026-01-%02d", id),
        updated_at = fields.updated_at or string.format("2026-02-%02d", id),
        epub_updated_at = fields.epub_updated_at or string.format("2026-03-%02d", id),
        progress = fields.progress or "",
        read = fields.read == true,
        deleted = fields.deleted == true,
    }
end

-- a reader sitting on one page of a document of ten. the reader modules answer
-- with a fraction of the document as laid out, which is what the plugin reads
-- rather than the reading state on disk.
local function reader(instance, id, page, pages)
    local events = {}
    instance.ui = {
        document = {
            file = "/library/newsletters/" .. id .. ".epub",
            info = { has_pages = false },
        },
        doc_settings = { readSetting = function() return { status = "reading" } end },
        rolling = {
            getLastPercent = function(self) return self.page / pages end,
            page = page,
        },
        handleEvent = function(_, event)
            events[#events + 1] = event
            if event.handler == "onGotoPercent" then
                instance.ui.rolling.page = math.floor(event.args[1] * pages / 100 + 0.5)
            end
        end,
    }
    return events
end

test("cache orders unread newsletters newest first and preserves downloaded epubs", function()
    reset_environment()
    local first = cache()
    first:put(row(1, { created_at = "2026-01-03", read = true }))
    first:put(row(2, { created_at = "2026-01-02" }))
    first:put(row(3, { created_at = "2026-01-01" }))
    first:setDownloaded(2, "2026-03-02")
    first:put(row(2, { created_at = "2026-01-02", epub_updated_at = "2026-04-02" }))

    local list = first:list()
    assert_equal(list[1].id, 2)
    assert_equal(list[2].id, 3)
    assert_equal(list[3].id, 1)
    assert_equal(first:downloads()[1].id, 3)
    assert_equal(first:downloads()[2].id, 2)

    local restarted = cache()
    assert_equal(restarted:get(2).downloaded_epub_updated_at, "2026-03-02")
end)

test("registers an unread-first sort mode that decorates newsletter rows", function()
    reset_environment()
    local instance = tribune()
    instance.ui = { menu = { registerToMainMenu = function() end } }
    instance.cache:put(row(8, { created_at = "2026-01-02", read = true }))
    instance.cache:put(row(9, { created_at = "2026-01-03" }))

    instance:init()

    local sort_mode = sort_mode_of(instance)
    assert_equal(sort_mode.text, "unread first")

    local older_unread = { text = "8.epub", path = "/library/newsletters/8.epub", attr = { size = 1 } }
    local newer_unread = { text = "9.epub", path = "/library/newsletters/9.epub", attr = { size = 1 } }
    sort_mode.item_func(older_unread)
    sort_mode.item_func(newer_unread)
    assert_equal(sort_mode.mandatory_func(newer_unread), "2026-01-03")
    assert_equal(newer_unread.text, "9")

    local read = { text = "8.epub", path = "/library/newsletters/8.epub", attr = { size = 1 } }
    sort_mode.item_func(read)
    assert_equal(sort_mode.mandatory_func(read), "✓ 2026-01-02")
    assert_true(read.dim)
    assert_equal(newer_unread.dim, nil)

    local compare = sort_mode.init_sort_func()
    assert_true(compare(newer_unread, older_unread))
    instance:onCloseWidget()
end)

test("an unindexed newsletter displays its cached title instead of its storage id", function()
    reset_environment()
    local instance = tribune()
    instance.ui = { menu = { registerToMainMenu = function() end } }
    instance.cache:put(row(6189, { title = "A link source" }))
    instance:init()

    local item = { text = "6189.epub", path = "/library/newsletters/6189.epub", attr = { size = 1 } }
    sort_mode_of(instance).item_func(item)

    assert_equal(item.text, "A link source")
    instance:onCloseWidget()
end)

test("unread-first sorting matches the other clients including id ties", function()
    reset_environment()
    local instance = tribune()
    instance.ui = { menu = { registerToMainMenu = function() end } }
    instance.cache:put(row(2, { created_at = "2026-01-03", read = true }))
    instance.cache:put(row(3, { created_at = "2026-01-02" }))
    instance.cache:put(row(4, { created_at = "2026-01-03" }))
    instance.cache:put(row(5, { created_at = "2026-01-03" }))
    instance:init()

    local sort_mode = sort_mode_of(instance)
    local items = {}
    for _, id in ipairs({ 2, 3, 4, 5 }) do
        local item = { text = id .. ".epub", path = "/library/newsletters/" .. id .. ".epub", attr = { size = 1 } }
        sort_mode.item_func(item)
        items[#items + 1] = item
    end
    table.sort(items, sort_mode.init_sort_func())

    assert_equal(items[1].text, "5")
    assert_equal(items[2].text, "4")
    assert_equal(items[3].text, "3")
    assert_equal(items[4].text, "2")
    instance:onCloseWidget()
end)

test("unread-first sorting reads cached newsletter state once per file", function()
    reset_environment()
    local lookups = 0
    local local_cache = {
        get = function(_, id)
            lookups = lookups + 1
            return { created_at = "2026-01-0" .. id, read = false }
        end,
    }
    local instance = tribune(local_cache)
    instance.ui = { menu = { registerToMainMenu = function() end } }
    instance:init()

    local sort_mode = sort_mode_of(instance)
    local items = {}
    for id = 1, 20 do
        local item = { text = id .. ".epub", path = "/library/newsletters/" .. id .. ".epub", attr = { size = 1 } }
        sort_mode.item_func(item)
        items[#items + 1] = item
    end
    table.sort(items, sort_mode.init_sort_func())

    assert_equal(lookups, 20)
    instance:onCloseWidget()
end)

test("the sort mode never joins the browser's own sort modes", function()
    reset_environment()
    local instance = tribune()
    instance.ui = { menu = { registerToMainMenu = function() end } }
    instance:init()

    -- nothing the browser can offer in its Sort by menu, and so nothing it can
    -- save the name of and fail to find on the next launch
    local FileChooser = require("ui/widget/filechooser")
    for id in pairs(FileChooser.collates) do
        assert_true(id == "strcoll")
    end

    instance:onCloseWidget()

    local restored, restored_id = browser_at(instance.newsletters_dir):getCollate()
    assert_equal(restored.text, "name")
    assert_equal(restored_id, "strcoll")
end)

test("the library folder is recognised through a symlinked storage path", function()
    reset_environment()
    local instance = tribune()
    instance.ui = { menu = { registerToMainMenu = function() end } }
    instance:init()
    -- what android and the kindle both do: the browser resolves the path it was
    -- handed, so it is never the string the plugin built its own path from
    resolved_paths["/library/newsletters"] = "/storage/emulated/0/newsletters"

    local collate, collate_id = browser_at("/storage/emulated/0/newsletters"):getCollate()

    assert_equal(collate.text, "unread first")
    assert_equal(collate_id, "tribune_unread_first")
    instance:onCloseWidget()
end)

test("the newsletters folder uses unread-first without changing other folders", function()
    reset_environment()
    local instance = tribune()
    instance.ui = { menu = { registerToMainMenu = function() end } }
    instance:init()
    local browser = browser_at("/library")

    local outside, outside_id = browser:getCollate()
    assert_equal(outside.text, "name")
    assert_equal(outside_id, "strcoll")

    browser.path = "/library/newsletters"
    local library, library_id = browser:getCollate()
    assert_equal(library.text, "unread first")
    assert_equal(library_id, "tribune_unread_first")
    instance:onCloseWidget()
end)

test("a browser rebuilt after the plugin started still orders the library", function()
    reset_environment()
    local instance = tribune()
    instance.ui = { menu = { registerToMainMenu = function() end } }
    instance:init()

    -- android throws the file browser away and builds another whenever the
    -- window changes shape, without the plugin being told
    local rebuilt = browser_at("/library/newsletters")
    local collate, collate_id = rebuilt:getCollate()

    assert_equal(collate.text, "unread first")
    assert_equal(collate_id, "tribune_unread_first")
    instance:onCloseWidget()
    assert_equal((rebuilt:getCollate()).text, "name")
end)

test("returning to the newsletters folder refreshes it with unread-first sorting", function()
    reset_environment()
    local refreshes = 0
    local browser = browser_at("/library/newsletters")
    browser.refreshPath = function() refreshes = refreshes + 1 end
    local instance = tribune()
    instance.ui = {
        menu = { registerToMainMenu = function() end },
        file_chooser = browser,
    }

    instance:init()

    assert_equal(refreshes, 1)
    instance:onCloseWidget()
end)

test("a synced read-state change refreshes unread-first ordering", function()
    reset_environment()
    local local_cache = cache()
    local_cache:put(row(1, { created_at = "2026-01-03" }))
    local_cache:put(row(2, { created_at = "2026-01-02" }))
    local_cache:setDownloaded(2, local_cache:get(2).epub_updated_at)
    local refreshes = 0
    local instance = tribune(local_cache)
    instance.ui = {
        menu = { registerToMainMenu = function() end },
        file_chooser = { refreshPath = function() refreshes = refreshes + 1 end },
    }
    instance:init()
    instance.request = function()
        return true, { result = { row(1, { created_at = "2026-01-03", read = true }) } }, 200
    end

    assert_true(instance:sync())
    assert_equal(refreshes, 1)

    local sort_mode = sort_mode_of(instance)
    local changed = { text = "1.epub", path = "/library/newsletters/1.epub", attr = { size = 1 } }
    local unread = { text = "2.epub", path = "/library/newsletters/2.epub", attr = { size = 1 } }
    sort_mode.item_func(changed)
    sort_mode.item_func(unread)
    assert_true(sort_mode.init_sort_func()(unread, changed))
    instance:onCloseWidget()
end)

test("the Library menu entry opens the newsletters folder", function()
    reset_environment()
    local opened_path
    local instance = tribune()
    instance.ui = {
        file_chooser = {
            changeToPath = function(_, path) opened_path = path end,
        },
    }
    local menu_items = {}
    instance:addToMainMenu(menu_items)

    menu_items.tribune.sub_item_table[4].callback()

    assert_equal(opened_path, "/library/newsletters")
    assert_true(directories["/library/newsletters"])
end)

test("signing out removes downloaded newsletters and their reading sidecars", function()
    reset_environment()
    local instance = tribune()
    instance.settings = {
        delSetting = function() end,
        flush = function() end,
    }
    instance.cache:put(row(7))
    instance.cache:setDownloaded(7, "2026-03-07")
    files["/library/newsletters/7.epub"] = "epub seven"

    instance:signOut()

    assert_equal(files["/library/newsletters/7.epub"], nil)
    assert_equal(purged[1], "/library/newsletters/7.epub")
end)

test("long-pressing a newsletter offers read unread and delete actions", function()
    reset_environment()
    local rows = {}
    local instance = tribune()
    instance.ui = {
        menu = { registerToMainMenu = function() end },
        addFileDialogButtons = function(_, id, row) rows[id] = row end,
    }

    instance:init()

    local actions = rows.tribune_newsletter_actions("/library/newsletters/7.epub", true)
    assert_equal(actions[1].text, "Mark as read")
    assert_equal(actions[2].text, "Mark as unread")
    assert_equal(actions[3].text, "Delete")
    assert_equal(rows.tribune_newsletter_actions("/library/other.epub", true), nil)
    assert_equal(rows.tribune_newsletter_actions("/library/newsletters/7.epub", false), nil)
end)

-- the kindle has no data dir of its own, so koreader calls its own directory
-- "." and the library path is relative, while the browser hands back absolute
-- paths. the actions have to appear there too.
test("long-pressing a newsletter offers its actions under a relative data dir", function()
    reset_environment()
    local rows = {}
    local instance = tribune()
    instance.newsletters_dir = "./newsletters"
    resolved_paths["./newsletters"] = "/mnt/us/koreader/newsletters"
    instance.ui = {
        menu = { registerToMainMenu = function() end },
        addFileDialogButtons = function(_, id, row) rows[id] = row end,
    }

    instance:init()

    local actions = rows.tribune_newsletter_actions("/mnt/us/koreader/newsletters/7.epub", true)
    assert_equal(actions[1].text, "Mark as read")
    assert_equal(rows.tribune_newsletter_actions("/mnt/us/koreader/books/7.epub", true), nil)
end)

test("a newsletter action closes the long-press dialog it was chosen from", function()
    reset_environment()
    local rows = {}
    local instance = tribune()
    instance.cache:put(row(7))
    local dialog = {}
    instance.ui = {
        menu = { registerToMainMenu = function() end },
        addFileDialogButtons = function(_, id, action_row) rows[id] = action_row end,
        file_chooser = { file_dialog = dialog, refreshPath = function() end },
    }
    instance:init()

    local actions = rows.tribune_newsletter_actions("/library/newsletters/7.epub", true)
    for _, action in ipairs(actions) do
        closed = {}
        action.callback()
        assert_equal(closed[1], dialog)
    end
end)

test("closing the file-browser plugin unregisters its long-press actions", function()
    reset_environment()
    local added, removed
    local instance = tribune()
    instance.ui = {
        menu = { registerToMainMenu = function() end },
        addFileDialogButtons = function(_, id) added = id end,
        removeFileDialogButtons = function(_, id) removed = id end,
    }

    instance:init()
    instance:onCloseWidget()

    assert_equal(added, "tribune_newsletter_actions")
    assert_equal(removed, "tribune_newsletter_actions")
end)

test("marking a newsletter read changes the cached state and queues an update", function()
    reset_environment()
    local rows, refreshes = {}, 0
    local instance = tribune()
    instance.cache:put(row(7))
    instance.ui = {
        menu = { registerToMainMenu = function() end },
        addFileDialogButtons = function(_, id, action_row) rows[id] = action_row end,
        file_chooser = { refreshPath = function() refreshes = refreshes + 1 end },
    }
    instance:init()

    rows.tribune_newsletter_actions("/library/newsletters/7.epub", true)[1].callback()

    assert_true(instance.cache:get(7).read)
    assert_equal(instance.cache:pendingUpdates()[1].kind, "read")
    assert_equal(instance.cache:pendingUpdates()[1].id, 7)
    assert_equal(refreshes, 1)
    assert_equal(#scheduled, 1)

    local quiet
    instance.autoSync = function(_, value) quiet = value end
    scheduled[1]()
    assert_equal(quiet, true)
end)

test("sync sends a queued read update before fetching newsletters", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7))
    instance:markNewsletterRead(7)
    local requests = {}
    instance.request = function(_, method, path)
        requests[#requests + 1] = { method = method, path = path }
        if method == "GET" then return true, { result = {} }, 200 end
        return true, {}, 200
    end

    assert_true(instance:sync())

    assert_equal(requests[1].method, "PUT")
    assert_equal(requests[1].path, "/newsletters/7/read")
    assert_equal(requests[2].method, "GET")
    assert_equal(#instance.cache:pendingUpdates(), 0)
end)

test("unread and delete actions update the device and use their server routes", function()
    reset_environment()
    local rows = {}
    local instance = tribune()
    instance.cache:put(row(7, { read = true }))
    instance.cache:put(row(8))
    instance.ui = {
        menu = { registerToMainMenu = function() end },
        addFileDialogButtons = function(_, id, action_row) rows[id] = action_row end,
        file_chooser = { refreshPath = function() end },
    }
    instance:init()
    rows.tribune_newsletter_actions("/library/newsletters/7.epub", true)[2].callback()
    rows.tribune_newsletter_actions("/library/newsletters/8.epub", true)[3].callback()
    assert_equal(#scheduled, 2)
    local quiet = {}
    instance.autoSync = function(_, value) quiet[#quiet + 1] = value end
    scheduled[1]()
    scheduled[2]()
    assert_equal(quiet[1], true)
    assert_equal(quiet[2], true)
    local sent = {}
    instance.request = function(_, method, path)
        sent[#sent + 1] = method .. " " .. path
        if method == "GET" then return true, { result = {} }, 200 end
        return true, nil, 200
    end
    instance.downloadUnread = function() return true, 0 end

    assert_true(instance:sync())

    assert_equal(instance.cache:get(7).read, false)
    assert_true(instance.cache:get(8).deleted)
    assert_equal(sent[1], "PUT /newsletters/7/unread")
    assert_equal(sent[2], "DELETE /newsletters/8")
end)

test("offline read then unread keeps only the final persisted update after restart", function()
    reset_environment()
    local first = cache()
    first:put(row(7))
    first:setRead(7, true)
    first:queueUpdate({ kind = "read", id = 7 })
    first:setRead(7, false)
    first:queueUpdate({ kind = "unread", id = 7 })

    local restarted = cache()
    local updates = restarted:pendingUpdates()
    assert_equal(#updates, 1)
    assert_equal(updates[1].kind, "unread")
    assert_equal(updates[1].id, 7)
end)

test("a rejected update remains queued for a later sync", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7))
    instance:markNewsletterRead(7)
    instance.request = function(_, method)
        if method == "PUT" then return false, "rejected", 422 end
        fail("the library must not be fetched after a rejected update")
    end

    assert_equal(instance:sync(), false)
    assert_equal(#instance.cache:pendingUpdates(), 1)
end)

test("updates that remain undeliverable for thirty days expire", function()
    reset_environment()
    local local_cache = cache()
    local now = 1800000000
    local_cache:queueUpdate({ kind = "read", id = 7, queued_at = now - 30 * 24 * 60 * 60 - 1 })
    local_cache:queueUpdate({ kind = "delete", id = 8, queued_at = now - 30 * 24 * 60 * 60 })

    local_cache:expirePendingUpdates(now)

    local updates = local_cache:pendingUpdates()
    assert_equal(#updates, 1)
    assert_equal(updates[1].id, 8)
end)

test("closing a finished newsletter marks it read but an unfinished one does not", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7))
    instance.ui = {
        document = { file = "/library/newsletters/7.epub" },
        doc_settings = { readSetting = function() return { status = "complete" } end },
    }

    instance:onCloseDocument()

    assert_true(instance.cache:get(7).read)
    assert_equal(#instance.cache:pendingUpdates(), 1)

    reset_environment()
    instance = tribune()
    instance.cache:put(row(7))
    instance.ui = {
        document = { file = "/library/newsletters/7.epub" },
        doc_settings = { readSetting = function() return { status = "reading" } end },
    }

    instance:onCloseDocument()

    assert_equal(instance.cache:get(7).read, false)
    assert_equal(#instance.cache:pendingUpdates(), 0)
end)

test("reading partway through and closing sends the progress to the server", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7))
    local events = reader(instance, 7, 1, 10)

    instance:onReaderReady()
    instance.ui.rolling.page = 5
    instance:onCloseDocument()

    assert_equal(#events, 0)
    assert_equal(instance.cache:get(7).progress, "0.5000")
    assert_equal(instance.cache:pendingUpdates()[1].kind, "progress")
    assert_equal(instance.cache:pendingUpdates()[1].progress, "0.5000")

    local sent
    instance.request = function(_, method, path, body)
        if method == "GET" then return true, { result = {} }, 200 end
        sent = method .. " " .. path .. " " .. tostring(body)
        return true, nil, 200
    end
    instance.downloadUnread = function() return true, 0 end

    assert_true(instance:sync())
    assert_equal(sent, "PUT /newsletters/7/progress progress=0.5000")
    assert_equal(#instance.cache:pendingUpdates(), 0)
end)

test("opening a newsletter seeks to the progress the server knows about", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7, { progress = "0.6000" }))
    local events = reader(instance, 7, 1, 10)

    instance:onReaderReady()

    assert_equal(#events, 1)
    assert_equal(events[1].handler, "onGotoPercent")
    assert_equal(events[1].args[1], 60)
    assert_equal(instance.ui.rolling.page, 6)
end)

test("a progress still queued on the device is not overwritten by the server's", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7, { progress = "0.2000" }))
    instance.cache:setProgress(7, "0.8000")
    instance.cache:queueUpdate({ kind = "progress", id = 7, progress = "0.8000" })
    local events = reader(instance, 7, 8, 10)

    instance:onReaderReady()

    assert_equal(#events, 0)
    assert_equal(instance.ui.rolling.page, 8)
end)

test("an unreadable stored progress opens the newsletter at the beginning", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7, { progress = "epubcfi(/6/4!/4/2/2)" }))
    local events = reader(instance, 7, 1, 10)

    instance:onReaderReady()
    instance:onCloseDocument()

    assert_equal(#events, 0)
    assert_equal(#instance.cache:pendingUpdates(), 0)
end)

test("closing a newsletter without reading further sends no progress", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7, { progress = "0.6000" }))
    reader(instance, 7, 1, 10)

    instance:onReaderReady()
    instance:onCloseDocument()

    assert_equal(instance.cache:get(7).progress, "0.6000")
    assert_equal(#instance.cache:pendingUpdates(), 0)
end)

test("turning many pages queues one progress rather than one per page", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7))
    reader(instance, 7, 1, 10)

    instance:onReaderReady()
    for page = 2, 10 do
        instance.ui.rolling.page = page
        assert_equal(#instance.cache:pendingUpdates(), 0)
    end
    instance:onCloseDocument()

    local updates = instance.cache:pendingUpdates()
    assert_equal(#updates, 1)
    assert_equal(updates[1].progress, "1.0000")
end)

test("repeated readings coalesce into one queued progress", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7))

    -- the third of these does not move, so it has nothing of its own to say and
    -- leaves the position queued by the second one where it is
    for _, page in ipairs({ 3, 5, 5, 9 }) do
        reader(instance, 7, 1, 10)
        instance:onReaderReady()
        instance.ui.rolling.page = page
        instance:onCloseDocument()
        assert_equal(#instance.cache:pendingUpdates(), 1)
    end

    assert_equal(instance.cache:pendingUpdates()[1].progress, "0.9000")
    assert_equal(instance.cache:get(7).progress, "0.9000")
end)

-- coalescing is about what is still waiting, not about what has already gone.
-- a reading that syncs before the next one begins is its own update.
test("a sync between two readings sends each one's final position", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7))
    local sent = {}
    instance.request = function(_, method, path, body)
        if method == "GET" then return true, { result = {} }, 200 end
        sent[#sent + 1] = path .. " " .. tostring(body)
        return true, nil, 200
    end
    instance.downloadUnread = function() return true, 0 end

    for _, page in ipairs({ 3, 8 }) do
        reader(instance, 7, 1, 10)
        instance:onReaderReady()
        instance.ui.rolling.page = page
        instance:onCloseDocument()
        assert_true(instance:sync())
    end

    assert_equal(#sent, 2)
    assert_equal(sent[1], "/newsletters/7/progress progress=0.3000")
    assert_equal(sent[2], "/newsletters/7/progress progress=0.8000")
end)

test("progress is truncated to four decimal places like the other clients", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7))
    reader(instance, 7, 1, 3)

    instance:onReaderReady()
    instance.ui.rolling.page = 2
    instance:onCloseDocument()

    assert_equal(instance.cache:get(7).progress, "0.6666")
end)

-- the same fixtures web/tests/ReadingPosition.spec.ts pins on its own quantiser.
-- what makes a fraction carry between renderers is that neither of them rounds
-- differently from the other, so both suites are held to the same values.
test("progress is written in the form the other clients write", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7))
    for _, case in ipairs({
        { fraction = 0.123456, stored = "0.1234" },
        { fraction = 0.99999, stored = "0.9999" },
        { fraction = 0, stored = "0.0000" },
        { fraction = 1, stored = "1.0000" },
    }) do
        reader(instance, 7, 1, 10)
        instance:onReaderReady()
        instance.ui.rolling.getLastPercent = function() return case.fraction end
        instance:onCloseDocument()
        assert_equal(instance.cache:get(7).progress, case.stored)
    end
end)

test("a stored progress is read in the form the other clients read", function()
    reset_environment()
    local instance = tribune()

    -- a renderer that quantised further out still lands on our fraction
    for _, stored in ipairs({ "0.3519", "0.35196" }) do
        instance.cache:put(row(7, { progress = stored }))
        local events = reader(instance, 7, 1, 10)
        instance:onReaderReady()
        assert_equal(#events, 1)
        assert_equal(string.format("%.4f", events[1].args[1] / 100), "0.3519")
    end

    -- anything that is not a fraction means the newsletter has never been
    -- opened, which is how the cfis stored before the change retire
    for _, stored in ipairs({ "epubcfi(/6/2!/4/2/2/2)", "", "   ", "halfway", "1.5", "-0.2" }) do
        instance.cache:put(row(7, { progress = stored }))
        local events = reader(instance, 7, 1, 10)
        instance:onReaderReady()
        assert_equal(#events, 0)
    end
end)

test("reaching the end of a newsletter does not on its own mark it read", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7))
    reader(instance, 7, 1, 10)

    instance:onReaderReady()
    instance.ui.rolling.page = 10
    instance:onCloseDocument()

    assert_equal(instance.cache:get(7).read, false)
    local updates = instance.cache:pendingUpdates()
    assert_equal(#updates, 1)
    assert_equal(updates[1].kind, "progress")
    assert_equal(updates[1].progress, "1.0000")
end)

test("progress recorded offline is sent on the next sync", function()
    reset_environment()
    local first = cache()
    first:put(row(7))
    local instance = tribune(first)
    reader(instance, 7, 1, 10)
    instance:onReaderReady()
    instance.ui.rolling.page = 4
    instance:onCloseDocument()

    instance.request = function() return false, "offline", nil end
    assert_equal(instance:sync(), false)

    local restarted = tribune(cache())
    assert_equal(restarted.cache:pendingUpdates()[1].progress, "0.4000")
    local sent = {}
    restarted.request = function(_, method, path, body)
        if method == "GET" then return true, { result = {} }, 200 end
        sent[#sent + 1] = method .. " " .. path .. " " .. tostring(body)
        return true, nil, 200
    end
    restarted.downloadUnread = function() return true, 0 end

    assert_true(restarted:sync())
    assert_equal(sent[1], "PUT /newsletters/7/progress progress=0.4000")
    assert_equal(#restarted.cache:pendingUpdates(), 0)
end)

test("a synced progress from another client replaces the cached one", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(7, { progress = "0.1000" }))
    instance.cache:setDownloaded(7, instance.cache:get(7).epub_updated_at)
    instance.request = function()
        return true, { result = { row(7, { progress = "0.7500" }) } }, 200
    end

    assert_true(instance:sync())

    assert_equal(instance.cache:get(7).progress, "0.7500")
    assert_equal(instance.cache:get(7).downloaded_epub_updated_at, "2026-03-07")
end)

test("sync pages from an empty cache and resumes after an interrupted page", function()
    reset_environment()
    local instance = tribune()
    local first_page = {}
    for id = 1, 100 do first_page[id] = row(id, { read = true }) end
    local calls = 0
    instance.request = function()
        calls = calls + 1
        if calls == 1 then return true, { result = first_page }, 200 end
        return false, "offline", nil
    end

    local ok = instance:sync()
    assert_equal(ok, false)
    assert_equal(instance.cache:getCursor().id, 100)

    instance.request = function() return true, { result = { row(101, { read = true }) } }, 200 end
    local resumed, summary = instance:sync()
    assert_true(resumed)
    assert_equal(summary.fetched, 1)
    assert_equal(instance.cache:getCursor().id, 101)
end)

test("sync leaves deleted newsletters out of the library", function()
    reset_environment()
    local instance = tribune()
    instance.request = function() return true, { result = { row(1, { read = true }), row(2, { deleted = true }) } }, 200 end
    assert_true(instance:sync())
    assert_equal(#instance.cache:list(), 1)
    assert_equal(instance.cache:list()[1].id, 1)
end)

test("a sync on an offline device keeps the cached library and explains that it did not run", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(1, { read = true }))
    instance:autoSync()

    assert_equal(instance.cache:list()[1].id, 1)
    assert_equal(messages[1].text, "Tribune did not sync: this device is offline.")
end)

test("a background sync does not ask for the wifi to be brought up", function()
    reset_environment()
    network.wifi_on = true
    network.connected = true
    local instance = tribune()
    instance.request = function() return true, { result = {} }, 200 end

    instance:autoSync()

    assert_equal(network.callback, nil)
    assert_true(instance.cache:getLastSync() ~= nil)
end)

test("tapping Library syncs the folder it opens", function()
    reset_environment()
    network.wifi_on = true
    network.connected = true
    local instance = tribune()
    instance.ui = { file_chooser = { changeToPath = function() end, refreshPath = function() end } }
    instance.request = function() return true, { result = {} }, 200 end
    local menu_items = {}
    instance:addToMainMenu(menu_items)

    menu_items.tribune.sub_item_table[4].callback()
    assert_equal(#scheduled, 1)
    scheduled[1]()

    assert_true(instance.cache:getLastSync() ~= nil)
end)

test("tapping Library offline leaves the library alone and says why", function()
    reset_environment()
    local instance = tribune()
    instance.ui = { file_chooser = { changeToPath = function() end } }
    instance.request = function() fail("an offline device must not be asked") end
    local menu_items = {}
    instance:addToMainMenu(menu_items)

    menu_items.tribune.sub_item_table[4].callback()
    scheduled[1]()

    assert_equal(instance.cache:getLastSync(), nil)
    assert_equal(messages[1].text, "Tribune did not sync: this device is offline.")
end)

test("opening the browser does not sync on its own", function()
    reset_environment()
    local instance = tribune()
    instance.ui = { menu = { registerToMainMenu = function() end } }
    instance.request = function() fail("opening the browser must not sync") end

    instance:init()

    assert_equal(#scheduled, 0)
    instance:onCloseWidget()
end)

test("coming back from a newsletter syncs", function()
    reset_environment()
    network.wifi_on = true
    network.connected = true
    local local_cache = cache()
    local_cache:put(row(7))
    local reading = tribune(local_cache)
    reader(reading, 7, 1, 10)
    reading:onReaderReady()
    reading.ui.rolling.page = 5
    reading:onCloseDocument()

    -- the browser that comes back is a new plugin opening the cache for itself,
    -- so it only has the position if closing the book wrote it down first
    local returned = tribune(cache())
    returned.ui = { menu = { registerToMainMenu = function() end } }
    returned.request = function(_, method)
        if method == "GET" then return true, { result = {} }, 200 end
        return true, nil, 200
    end
    http_response = function(request)
        request.sink("epub seven")
        return 1, 200, {}, "200 OK"
    end
    returned:init()
    assert_equal(#scheduled, 1)
    scheduled[1]()

    -- the sync sent the position the reader queued, so it was on the queue
    -- before the sync was scheduled rather than after it
    assert_equal(#returned.cache:pendingUpdates(), 0)
    assert_equal(returned.cache:get(7).progress, "0.5000")
    returned:onCloseWidget()
end)

test("coming back from a newsletter offline says nothing about it", function()
    reset_environment()
    local local_cache = cache()
    local_cache:put(row(7))
    local reading = tribune(local_cache)
    reader(reading, 7, 1, 10)
    reading:onReaderReady()
    reading.ui.rolling.page = 5
    reading:onCloseDocument()

    local returned = tribune(cache())
    returned.ui = { menu = { registerToMainMenu = function() end } }
    returned:init()
    assert_equal(#scheduled, 1)
    scheduled[1]()

    assert_equal(#messages, 0)
    assert_equal(#returned.cache:pendingUpdates(), 1)
    returned:onCloseWidget()
end)

test("sync now asks the network manager to connect when the device is offline", function()
    reset_environment()
    network.rerun_when_connected = true
    local instance = tribune()

    instance:syncNow()

    assert_true(type(network.callback) == "function")
end)

test("download writes an unread epub under its newsletter id", function()
    reset_environment()
    local local_cache = cache()
    local_cache:put(row(7))
    local instance = tribune(local_cache)
    http_response = function(request)
        request.sink("epub seven")
        return 1, 200, {}, "200 OK"
    end

    local ok, count = instance:downloadUnread()
    assert_true(ok)
    assert_equal(count, 1)
    assert_equal(files["/library/newsletters/7.epub"], "epub seven")
    assert_equal(local_cache:get(7).downloaded_epub_updated_at, "2026-03-07")
end)

test("download fetches every unread newsletter from oldest to newest", function()
    reset_environment()
    local local_cache = cache()
    local_cache:put(row(9, { created_at = "2026-01-03" }))
    local_cache:put(row(7, { created_at = "2026-01-01" }))
    local_cache:put(row(8, { created_at = "2026-01-02" }))
    local instance = tribune(local_cache)
    local paths = {}
    http_response = function(request)
        paths[#paths + 1] = request.url
        request.sink("epub")
        return 1, 200, {}, "200 OK"
    end

    local ok, count = instance:downloadUnread()
    assert_true(ok)
    assert_equal(count, 3)
    assert_equal(paths[1], "http://tribune.test/newsletters/7/epub")
    assert_equal(paths[2], "http://tribune.test/newsletters/8/epub")
    assert_equal(paths[3], "http://tribune.test/newsletters/9/epub")
end)

test("download skips read deleted and unchanged newsletters", function()
    reset_environment()
    local local_cache = cache()
    local_cache:put(row(1, { read = true }))
    local_cache:put(row(2, { deleted = true }))
    local_cache:put(row(3))
    local_cache:setDownloaded(3, "2026-03-03")
    local instance = tribune(local_cache)
    local requests = 0
    http_response = function()
        requests = requests + 1
        return 1, 200, {}, "200 OK"
    end

    local ok, count = instance:downloadUnread()
    assert_true(ok)
    assert_equal(count, 0)
    assert_equal(requests, 0)
end)

test("a regenerated epub replaces the file and clears its reading sidecar", function()
    reset_environment()
    local local_cache = cache()
    local_cache:put(row(4, { epub_updated_at = "new" }))
    local_cache:setDownloaded(4, "old")
    files["/library/newsletters/4.epub"] = "old epub"
    local instance = tribune(local_cache)
    http_response = function(request)
        request.sink("new epub")
        return 1, 200, {}, "200 OK"
    end

    assert_true(instance:downloadUnread())
    assert_equal(files["/library/newsletters/4.epub"], "new epub")
    assert_equal(local_cache:get(4).downloaded_epub_updated_at, "new")
    assert_equal(purged[1], "/library/newsletters/4.epub")
end)

test("download stops before requesting an epub when less than a gigabyte is free", function()
    reset_environment()
    free_space = 1024 * 1024 * 1024 - 1
    local local_cache = cache()
    local_cache:put(row(5))
    local instance = tribune(local_cache)
    http_response = function() fail("download should not start") end

    local ok, message = instance:downloadUnread()
    assert_equal(ok, false)
    assert_true(message:match("less than 1 GB") ~= nil)
end)

test("download continues when free space cannot be determined", function()
    reset_environment()
    local local_cache = cache()
    local_cache:put(row(6))
    local instance = tribune(local_cache)
    http_response = function(request)
        request.sink("epub six")
        return 1, 200, {}, "200 OK"
    end

    assert_true(instance:downloadUnread())
    assert_equal(files["/library/newsletters/6.epub"], "epub six")
end)

test("a failed download removes its partial epub and leaves the cache pending", function()
    reset_environment()
    local local_cache = cache()
    local_cache:put(row(8))
    local instance = tribune(local_cache)
    http_response = function(request)
        request.sink("incomplete")
        return nil, "timeout"
    end

    local ok = instance:downloadUnread()
    assert_equal(ok, false)
    assert_equal(files["/library/newsletters/8.epub.partial"], nil)
    assert_equal(files["/library/newsletters/8.epub"], nil)
    assert_equal(local_cache:get(8).downloaded_epub_updated_at, nil)
end)

--[[ eviction ]]--

-- an epub that arrived at NOW and has not been opened since. three days is what
-- the other clients wait too, so the fixtures are written in days.
local NOW = 1800000000
local DAY = 24 * 60 * 60

local function downloaded(id, fields)
    local local_cache = cache()
    local_cache:put(row(id, fields))
    local_cache:setDownloaded(id, local_cache:get(id).epub_updated_at, NOW)
    files["/library/newsletters/" .. id .. ".epub"] = "epub " .. id
    return local_cache
end

test("a read newsletter's epub goes three days after it was last opened", function()
    reset_environment()
    local local_cache = downloaded(7, { read = true })
    local instance = tribune(local_cache)

    clock = NOW + 3 * DAY
    assert_equal(instance:evictDownloads(), 0)
    assert_equal(files["/library/newsletters/7.epub"], "epub 7")

    clock = NOW + 3 * DAY + 1
    assert_equal(instance:evictDownloads(), 1)
    assert_equal(files["/library/newsletters/7.epub"], nil)
    assert_equal(purged[1], "/library/newsletters/7.epub")
    assert_equal(local_cache:get(7).downloaded_epub_updated_at, nil)
end)

test("a deleted newsletter's epub goes on the same terms", function()
    reset_environment()
    local instance = tribune(downloaded(8, { deleted = true }))

    clock = NOW + 3 * DAY
    assert_equal(instance:evictDownloads(), 0)

    clock = NOW + 4 * DAY
    assert_equal(instance:evictDownloads(), 1)
    assert_equal(files["/library/newsletters/8.epub"], nil)
    assert_equal(purged[1], "/library/newsletters/8.epub")
end)

test("an unread newsletter's epub is kept however old it is", function()
    reset_environment()
    local local_cache = downloaded(9)
    local instance = tribune(local_cache)

    clock = NOW + 365 * DAY
    assert_equal(instance:evictDownloads(), 0)
    assert_equal(files["/library/newsletters/9.epub"], "epub 9")
    assert_equal(local_cache:get(9).downloaded_epub_updated_at, "2026-03-09")
end)

test("opening a newsletter defers the removal of its epub", function()
    reset_environment()
    local instance = tribune(downloaded(7, { read = true }))

    clock = NOW + 2 * DAY
    reader(instance, 7, 1, 10)
    instance:onReaderReady()

    clock = NOW + 4 * DAY
    assert_equal(instance:evictDownloads(), 0)
    assert_equal(files["/library/newsletters/7.epub"], "epub 7")

    clock = NOW + 5 * DAY + 1
    assert_equal(instance:evictDownloads(), 1)
    assert_equal(files["/library/newsletters/7.epub"], nil)
end)

test("a read state the server has not heard about keeps the epub", function()
    reset_environment()
    local instance = tribune(downloaded(7))
    clock = NOW + 4 * DAY
    instance:markNewsletterRead(7)

    instance.request = function() return false, "offline", nil end
    assert_equal(instance:sync(), false)
    assert_equal(files["/library/newsletters/7.epub"], "epub 7")

    instance.request = function(_, method)
        if method == "GET" then return true, { result = {} }, 200 end
        return true, nil, 200
    end
    -- this sync sends the update, so the file is still held while it runs
    assert_true(instance:sync())
    assert_equal(files["/library/newsletters/7.epub"], "epub 7")

    assert_true(instance:sync())
    assert_equal(files["/library/newsletters/7.epub"], nil)
end)

test("a delete the server has not heard about keeps the epub", function()
    reset_environment()
    local instance = tribune(downloaded(8))
    clock = NOW + 4 * DAY
    instance:deleteNewsletter(8)

    assert_equal(instance:evictDownloads(), 0)
    assert_equal(files["/library/newsletters/8.epub"], "epub 8")

    instance.request = function(_, method)
        if method == "GET" then return true, { result = {} }, 200 end
        return true, nil, 200
    end
    assert_true(instance:sync())

    assert_equal(instance:evictDownloads(), 1)
    assert_equal(files["/library/newsletters/8.epub"], nil)
end)

-- the other side of the same rule. a queued position is not what the file is
-- being dropped for, and removing the file does not take it with it.
test("a queued progress does not hold an epub on the device", function()
    reset_environment()
    local instance = tribune(downloaded(7, { read = true }))
    instance.cache:queueUpdate({ kind = "progress", id = 7, progress = "0.5000" })

    clock = NOW + 4 * DAY
    assert_equal(instance:evictDownloads(), 1)
    assert_equal(files["/library/newsletters/7.epub"], nil)
    assert_equal(#instance.cache:pendingUpdates(), 1)
end)

test("an epub downloaded before the clock existed starts its wait rather than staying for good", function()
    reset_environment()
    local local_cache = cache()
    local_cache:put(row(7, { read = true }))
    local_cache:setDownloaded(7, "2026-03-07", NOW)
    local_cache:get(7).epub_accessed_at = nil
    local_cache.data:saveSetting(7, local_cache:get(7))
    files["/library/newsletters/7.epub"] = "epub 7"
    local instance = tribune(local_cache)

    assert_equal(instance:evictDownloads(NOW), 0)
    assert_equal(local_cache:get(7).epub_accessed_at, NOW)

    assert_equal(instance:evictDownloads(NOW + 4 * DAY), 1)
    assert_equal(files["/library/newsletters/7.epub"], nil)
end)

test("a removed newsletter is not downloaded again on the next sync", function()
    reset_environment()
    local instance = tribune(downloaded(7, { read = true }))
    instance.request = function(_, method)
        if method == "GET" then return true, { result = {} }, 200 end
        return true, nil, 200
    end
    http_response = function() fail("a removed newsletter must not be fetched again") end

    clock = NOW + 4 * DAY
    local ok, summary = instance:sync()
    assert_true(ok)
    assert_equal(summary.removed, 1)
    assert_equal(files["/library/newsletters/7.epub"], nil)

    local resynced, next_summary = instance:sync()
    assert_true(resynced)
    assert_equal(next_summary.downloaded, 0)
    assert_equal(files["/library/newsletters/7.epub"], nil)
end)

io.open = original_open
os.remove = original_remove
os.rename = original_rename
os.time = original_time

if failures > 0 then os.exit(1) end
