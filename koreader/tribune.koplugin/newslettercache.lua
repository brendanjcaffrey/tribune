--[[--
the plugin's own picture of the library.

only what the plugin needs is kept about a newsletter: its id, so it can be
named on disk and on the server; when it was published and whether it has been
read, so it can be ordered; when its epub last changed, so a downloaded copy can
be told from a stale one; whether it has been deleted, so it stops being listed;
and when it last changed, which is what the server pages on.

the file is append-mostly. writing one newsletter appends one line rather than
rewriting the library, because a sync of a few thousand newsletters would
otherwise rewrite a growing file once per page, and on a kindle that is slow
enough to notice. the whole file is rewritten only when the appends have made it
much bigger than the data in it.

@module koplugin.tribune.newslettercache
--]]--

local LuaData = require("luadata")
local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

-- the name luadata writes in front of every entry. it is part of the file
-- format, so changing it orphans every cache already on a device.
local ENTRY_NAME = "TribuneNewsletter"

-- roughly what one newsletter costs once written out. only used to guess
-- whether the appends have outgrown the data, so it does not have to be right.
local BYTES_PER_NEWSLETTER = 150
-- rewrite once the file is this many times bigger than the data it holds, and
-- only once there is enough of it for the ratio to mean anything.
local COMPACT_RATIO = 3
local COMPACT_FLOOR = 32 * 1024

local Cache = {}
Cache.__index = Cache

function Cache:open(path)
    local instance = setmetatable({
        path = path,
        data = LuaData:open(path, ENTRY_NAME),
    }, self)
    return instance
end

--[[ newsletters ]]--

-- one row as the server sent it, reduced to what is kept. every field is
-- written every time: luadata merges a single-field table into the entry
-- already there and only replaces one with more than one field, so a row that
-- shrank to one field would silently keep the values it was meant to lose.
local function reduce(row)
    return {
        created_at = row.created_at or "",
        updated_at = row.updated_at or "",
        epub_updated_at = row.epub_updated_at or "",
        read = row.read == true,
        deleted = row.deleted == true,
    }
end

-- upsert. anything the plugin has added of its own to a newsletter it already
-- knows about — which epub it has actually downloaded, say — is kept, because
-- the server has never heard of it and would otherwise wipe it every sync.
function Cache:put(row)
    local id = tonumber(row.id)
    if not id then return false end

    local kept = reduce(row)
    local existing = self.data:readSetting(id)
    if existing then
        for key, value in pairs(existing) do
            if kept[key] == nil then kept[key] = value end
        end
    end

    self.data:saveSetting(id, kept)
    return true
end

function Cache:get(id)
    return self.data:readSetting(tonumber(id))
end

-- every newsletter, deleted ones included. the keys are the ids.
function Cache:all()
    local out = {}
    for id, newsletter in pairs(self.data.data) do
        if type(id) == "number" then out[id] = newsletter end
    end
    return out
end

-- the newsletters worth showing: everything that has not been deleted, unread
-- first and then oldest published first, which is the order the other clients
-- read in.
function Cache:list()
    local out = {}
    for id, newsletter in pairs(self.data.data) do
        if type(id) == "number" and not newsletter.deleted then
            out[#out + 1] = {
                id = id,
                created_at = newsletter.created_at,
                updated_at = newsletter.updated_at,
                epub_updated_at = newsletter.epub_updated_at,
                read = newsletter.read,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.read ~= b.read then return b.read end
        if a.created_at ~= b.created_at then return a.created_at < b.created_at end
        return a.id < b.id
    end)
    return out
end

function Cache:counts()
    local total, unread = 0, 0
    for id, newsletter in pairs(self.data.data) do
        if type(id) == "number" and not newsletter.deleted then
            total = total + 1
            if not newsletter.read then unread = unread + 1 end
        end
    end
    return total, unread
end

-- records the version of an epub that made it safely onto the device. this is
-- deliberately separate from epub_updated_at: the latter is what the server
-- currently has, while this says which version the local file contains.
function Cache:setDownloaded(id, epub_updated_at)
    local newsletter = self:get(id)
    if not newsletter then return false end
    newsletter.downloaded_epub_updated_at = epub_updated_at
    self.data:saveSetting(tonumber(id), newsletter)
    return true
end

function Cache:isDownloadedCurrent(id)
    local newsletter = self:get(id)
    return newsletter
        and newsletter.downloaded_epub_updated_at == newsletter.epub_updated_at
end

-- unread, undeleted newsletters that need a local epub, in the library order.
function Cache:downloads()
    local out = {}
    for id, newsletter in pairs(self.data.data) do
        if type(id) == "number" and not newsletter.deleted and not newsletter.read
            and newsletter.epub_updated_at ~= ""
            and newsletter.downloaded_epub_updated_at ~= newsletter.epub_updated_at then
            out[#out + 1] = { id = id, created_at = newsletter.created_at }
        end
    end
    table.sort(out, function(a, b)
        if a.created_at ~= b.created_at then return a.created_at < b.created_at end
        return a.id < b.id
    end)
    return out
end

function Cache:isEmpty()
    for id in pairs(self.data.data) do
        if type(id) == "number" then return false end
    end
    return true
end

--[[ where the last sync got to ]]--

-- the cursor is the newest change the plugin is certain it has, as the pair the
-- server pages on. a sync moves it up one page at a time, once every row in
-- that page has been stored, so being killed halfway costs the page that was in
-- flight rather than everything the sync had covered.
function Cache:getCursor()
    return self.data:readSetting("cursor")
end

function Cache:setCursor(updated_at, id)
    self.data:saveSetting("cursor", { updated_at = updated_at, id = id })
end

-- when a sync last finished. only ever shown to the reader.
function Cache:getLastSync()
    return self.data:readSetting("last_sync")
end

function Cache:setLastSync(when)
    self.data:saveSetting("last_sync", when)
end

--[[ the file ]]--

-- rewrite the whole file when the appends have outgrown it. the new file is
-- built beside the old one and renamed over it, so there is no moment where the
-- cache on disk is half-written, and no pile of backups left behind.
function Cache:compactIfNeeded()
    local size = lfs.attributes(self.path, "size")
    if not size or size < COMPACT_FLOOR then return false end

    local entries = 0
    for _ in pairs(self.data.data) do entries = entries + 1 end
    if size < entries * BYTES_PER_NEWSLETTER * COMPACT_RATIO then return false end

    local temporary = self.path .. ".new"
    local out = io.open(temporary, "w")
    if not out then
        logger.warn("tribune: could not write", temporary)
        return false
    end
    -- one untagged entry holding the lot, which is how luadata reads a file
    -- back in when nothing has been appended to it yet
    out:write("-- tribune newsletter cache\n")
    out:write(ENTRY_NAME .. "Entry")
    out:write(dump(self.data.data))
    out:write("\n")
    out:close()
    if not os.rename(temporary, self.path) then
        logger.warn("tribune: could not replace", self.path)
        os.remove(temporary)
        return false
    end
    logger.dbg("tribune: cache compacted from", size, "bytes,", entries, "entries")
    return true
end

-- forget everything and start again from an empty file. pointing the plugin at
-- a different server has to do this, since ids belong to the server that issued
-- them.
function Cache:reset()
    self.data.data = {}
    os.remove(self.path)
    for i = 1, self.data.max_backups do
        os.remove(self.path .. ".old." .. i)
    end
    self.data = LuaData:open(self.path, ENTRY_NAME)
end

return Cache
