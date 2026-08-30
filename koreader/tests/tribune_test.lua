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
local files = {}
local purged = {}
local messages = {}
local free_space
local http_response
local network = {}

local function reset_environment()
    stored_settings = {}
    directories = { ["/library"] = true }
    files = {}
    purged = {}
    messages = {}
    free_space = nil
    http_response = nil
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
package.preload["luasettings"] = function() return { open = function() return {} end } end
package.preload["ui/uimanager"] = function()
    return { show = function(_, message) messages[#messages + 1] = message end, close = function() end,
             forceRePaint = function() end, tickAfterNext = function() end, nextTick = function() end }
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
    return { template = function(format, value) return format:gsub("%%1", tostring(value)) end }
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

local function row(id, fields)
    fields = fields or {}
    return {
        id = id,
        title = fields.title or "",
        created_at = fields.created_at or string.format("2026-01-%02d", id),
        updated_at = fields.updated_at or string.format("2026-02-%02d", id),
        epub_updated_at = fields.epub_updated_at or string.format("2026-03-%02d", id),
        read = fields.read == true,
        deleted = fields.deleted == true,
    }
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

    local FileChooser = require("ui/widget/filechooser")
    local sort_mode = FileChooser.collates.tribune_unread_first
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
    require("ui/widget/filechooser").collates.tribune_unread_first.item_func(item)

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

    local sort_mode = require("ui/widget/filechooser").collates.tribune_unread_first
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

    local sort_mode = require("ui/widget/filechooser").collates.tribune_unread_first
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

test("stopping the plugin removes its sort mode", function()
    reset_environment()
    local instance = tribune()
    instance.ui = { menu = { registerToMainMenu = function() end } }
    instance:init()
    local FileChooser = require("ui/widget/filechooser")
    assert_true(FileChooser.collates.tribune_unread_first ~= nil)

    FileChooser.selected_collate = "tribune_unread_first"
    instance:onCloseWidget()

    assert_equal(FileChooser.collates.tribune_unread_first, nil)
    local fallback, fallback_id = FileChooser:getCollate()
    assert_equal(fallback.text, "name")
    assert_equal(fallback_id, "strcoll")
end)

test("the newsletters folder uses unread-first without changing other folders", function()
    reset_environment()
    local post_init = {}
    local browser = {
        path = "/library",
        getCollate = function() return { text = "name" }, "strcoll" end,
    }
    local instance = tribune()
    instance.ui = {
        menu = { registerToMainMenu = function() end },
        registerPostInitCallback = function(_, callback) post_init[#post_init + 1] = callback end,
    }
    instance:init()
    instance.ui.file_chooser = browser
    post_init[1]()

    local outside, outside_id = browser:getCollate()
    assert_equal(outside.text, "name")
    assert_equal(outside_id, "strcoll")

    browser.path = "/library/newsletters"
    local library, library_id = browser:getCollate()
    assert_equal(library.text, "unread first")
    assert_equal(library_id, "tribune_unread_first")
    instance:onCloseWidget()
end)

test("returning to the newsletters folder refreshes it with unread-first sorting", function()
    reset_environment()
    local refreshes = 0
    local browser = {
        path = "/library/newsletters",
        getCollate = function() return { text = "name" }, "strcoll" end,
        refreshPath = function() refreshes = refreshes + 1 end,
    }
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

    local sort_mode = require("ui/widget/filechooser").collates.tribune_unread_first
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

test("opening the browser offline keeps the cached library and explains that it did not sync", function()
    reset_environment()
    local instance = tribune()
    instance.cache:put(row(1, { read = true }))
    instance:autoSync()

    assert_equal(instance.cache:list()[1].id, 1)
    assert_equal(messages[1].text, "Tribune did not sync: this device is offline.")
end)

test("opening the browser online syncs without requesting a wifi prompt", function()
    reset_environment()
    network.wifi_on = true
    network.connected = true
    local instance = tribune()
    instance.request = function() return true, { result = {} }, 200 end

    instance:autoSync()

    assert_equal(network.callback, nil)
    assert_true(instance.cache:getLastSync() ~= nil)
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

io.open = original_open
os.remove = original_remove
os.rename = original_rename

if failures > 0 then os.exit(1) end
