-- Gen4RangeFile: open one of the packed terrain files (chunks / heights /
-- permissions .bin) for ranged reads, with a fallback that needs nothing but
-- love.filesystem.read.
--
-- The ground reads these with love.filesystem.newFile + seek + read so a map
-- holds a few hundred KB of a 17 MB file.  On the Switch the version cache is
-- reachable only through CacheFs's prefix shim, and a File handle is exactly
-- the kind of loader that shim did not cover -- which is why every DS game
-- drew its buildings and sprites over the clear colour with no ground at all
-- (docs/switch.md).  The shim now redirects newFile too; this is the second
-- line: if a handle still will not open (a port whose File:seek misbehaves, a
-- loader wrapped in the wrong order), read the whole file once through
-- love.filesystem.read -- the path every other generated asset already loads
-- through -- and serve the same seek/read calls from the string.
--
-- Returns an object with :seek(pos) and :read(bytes), or nil, why.

local Gen4RangeFile = {}

local StringFile = {}
StringFile.__index = StringFile

function StringFile:seek(pos)
  pos = tonumber(pos)
  if not pos or pos < 0 or pos > #self.bytes then return false end
  self.pos = pos
  return true
end

function StringFile:read(bytes)
  bytes = tonumber(bytes)
  if not bytes or bytes <= 0 then return nil end
  local chunk = self.bytes:sub(self.pos + 1, self.pos + bytes)
  self.pos = self.pos + #chunk
  if chunk == "" then return nil end
  return chunk, #chunk
end

function StringFile:release() self.bytes = "" end
function StringFile:close() return true end

function Gen4RangeFile.open(path)
  local fs = love and love.filesystem
  if not (fs and type(path) == "string") then return nil, "no filesystem" end
  local why
  if type(fs.newFile) == "function" then
    local ok, file, err = pcall(fs.newFile, path, "r")
    if ok and file then return file end
    why = ok and err or file
  end
  if type(fs.read) == "function" then
    local ok, bytes = pcall(fs.read, path)
    if ok and type(bytes) == "string" and #bytes > 0 then
      local Logger = require("src.core.Logger")
      Logger.info("gen4 ground: %s read whole (%d bytes) -- newFile refused it (%s)",
                  path, #bytes, tostring(why))
      return setmetatable({ bytes = bytes, pos = 0 }, StringFile)
    end
  end
  return nil, why or "not found"
end

return Gen4RangeFile
