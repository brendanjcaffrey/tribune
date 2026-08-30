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
os.remove = function(path) files[path] = nil; return true end
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
        created_at = fields.created_at or string.format("2026-01-%02d", id),
        updated_at = fields.updated_at or string.format("2026-02-%02d", id),
        epub_updated_at = fields.epub_updated_at or string.format("2026-03-%02d", id),
        read = fields.read == true,
        deleted = fields.deleted == true,
    }
end

test("cache orders unread newsletters first and preserves downloaded epubs", function()
    reset_environment()
    local first = cache()
    first:put(row(1, { created_at = "2026-01-03", read = true }))
    first:put(row(2, { created_at = "2026-01-02" }))
    first:put(row(3, { created_at = "2026-01-01" }))
    first:setDownloaded(2, "2026-03-02")
    first:put(row(2, { created_at = "2026-01-02", epub_updated_at = "2026-04-02" }))

    local list = first:list()
    assert_equal(list[1].id, 3)
    assert_equal(list[2].id, 2)
    assert_equal(list[3].id, 1)
    assert_equal(first:downloads()[1].id, 3)
    assert_equal(first:downloads()[2].id, 2)

    local restarted = cache()
    assert_equal(restarted:get(2).downloaded_epub_updated_at, "2026-03-02")
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
