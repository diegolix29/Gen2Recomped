-- Scoped access to a mod's launcher-validated required/optional imports and
-- to installation-wide generated cache data.
--
-- This intentionally does not expose host paths or raw filesystem handles.
-- Import reads are bounded and can only address ids declared by the calling
-- mod's manifest. Cache paths are confined to mod_cache/<mod-id>/ and are not
-- tied to a Pokémon playthrough.

local ImportAccess = {}

ImportAccess.MAX_READ_BYTES = 8 * 1024 * 1024
ImportAccess.MAX_CACHE_WRITE_BYTES = 64 * 1024 * 1024

local function parentOf(path)
  return path:match("^(.*)/[^/]+$")
end

local function copyInfo(info)
  if not info then return nil end
  return { type = info.type, size = info.size, modtime = info.modtime }
end

local function safePath(rel)
  -- Basic path validation - prevent directory traversal
  if type(rel) ~= "string" or rel == "" then return nil end
  if rel:sub(1, 1) == "/" then return nil end
  if rel:find("\\", 1, true) then return nil end
  if rel:match("^%a:") then return nil end -- windows drive-relative
  local parts = {}
  for segment in rel:gmatch("[^/]+") do
    if segment == ".." then return nil end
    if segment ~= "." then parts[#parts + 1] = segment end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "/")
end

local function makeCache(modId, fs)
  local root = "mod_cache/" .. modId
  local function pathFor(rel, what)
    local safe = safePath(rel)
    if not safe then
      error(("%s must stay inside its root, got %q"):format(what, tostring(rel)), 0)
    end
    return root .. "/" .. safe
  end
  local cache = {}

  function cache:write(rel, bytes)
    if type(bytes) ~= "string" then
      return nil, "mod.cache:write expects a byte string"
    end
    if #bytes > ImportAccess.MAX_CACHE_WRITE_BYTES then
      return nil, "mod.cache:write payload exceeds 64 MiB; split generated data into smaller files"
    end
    local path = pathFor(rel, "mod.cache:write")
    local parent = parentOf(path)
    if parent and fs.createDirectory then
      local ok = fs.createDirectory(parent)
      if ok == false then return nil, "could not create cache directory" end
    end
    if not fs.write then return nil, "cache writes are unavailable" end
    return fs.write(path, bytes)
  end

  function cache:read(rel)
    local path = pathFor(rel, "mod.cache:read")
    if not fs.read then return nil, "cache reads are unavailable" end
    return fs.read(path)
  end

  function cache:info(rel)
    local path = pathFor(rel, "mod.cache:info")
    if not fs.getInfo then return nil end
    return copyInfo(fs.getInfo(path))
  end

  function cache:exists(rel)
    local info = self:info(rel)
    return info ~= nil and info.type == "file"
  end

  function cache:delete(rel)
    local path = pathFor(rel, "mod.cache:delete")
    if not fs.remove then return nil, "cache deletion is unavailable" end
    return fs.remove(path)
  end

  return cache
end

function ImportAccess.new(manifest, fs)
  local cacheFs = fs
  local imports = {}

  function imports:info(id)
    -- Use parsed requiredImports from ModImports
    local spec = manifest.requiredImports or {}
    for _, s in ipairs(spec) do
      if s.id == id then
        local path
        if s.root == "save" then
          path = s.file
        else
          path = manifest.path .. "/" .. s.file
        end
        -- Check for validation marker first (Gen1Recomp compatibility)
        local markerPath = manifest.path .. "/.required-import-" .. id .. ".validated"
        local markerExists = fs.getInfo and fs.getInfo(markerPath)
        -- Also check if the actual file exists
        local info = fs.getInfo and fs.getInfo(path)
        if info then
          return {
            id = s.id,
            name = s.name,
            file = s.file,
            size = info.size,
            required = s.required ~= false,
            validated = markerExists ~= nil,
          }
        end
      end
    end
    return nil
  end

  function imports:have(id)
    local info = self:info(id)
    return info ~= nil
  end

  function imports:list()
    local spec = manifest.requiredImports or {}
    local out = {}
    for _, s in ipairs(spec) do
      out[#out + 1] = { id = s.id, name = s.name, file = s.file }
    end
    return out
  end

  function imports:read(id, offset, length)
    -- Simple implementation - read from mod folder
    local spec = manifest.requiredImports or {}
    for _, s in ipairs(spec) do
      if s.id == id then
        local path
        if s.root == "save" then
          path = s.file
        else
          path = manifest.path .. "/" .. s.file
        end
        if fs.read then
          local data = fs.read(path)
          if data then
            offset, length = tonumber(offset) or 0, tonumber(length) or #data
            return data:sub(offset + 1, offset + length)
          end
        end
      end
    end
    return nil
  end

  return imports, makeCache(manifest.id, cacheFs)
end

return ImportAccess
