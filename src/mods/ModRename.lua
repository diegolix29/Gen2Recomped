-- WHEN A MOD CHANGES ITS ID.
--
-- Four things key on a mod's id, and none of them is inside the mod:
--
--   options.mods[id]          -- the enable state, and its generation chips
--   options.modOptions[id]    -- every option the player has set
--   save.modData[id]          -- the mod's own per-playthrough state
--   modstorage/<id>/          -- its files, if it uses the storage API
--
-- So changing the id in a manifest -- which is a one-line edit, and the right
-- edit when an id was wrong -- silently orphans all four.  The mod loads, and
-- every option it has snaps back to the schema default.  Reported exactly as
-- it feels from the outside: "changing the id made half of my effects turn
-- off".  Nothing is lost, but nothing can find it either.
--
-- A manifest can therefore say what it used to be called:
--
--   "previous_ids": ["OLD_ID", "EVEN_OLDER"]
--
-- ...and the first time this build sees the new id with no state of its own,
-- the old state moves across.  Once.  After that the new id has state and the
-- declaration is inert, so it can stay in the manifest forever -- which it
-- should, because the next player to update is on their own first time.
--
-- TWO RULES KEEP THIS FROM BEING A WAY TO STEAL SOMEBODY ELSE'S SETTINGS:
--
--   * An id that is CURRENTLY INSTALLED is never adopted from.  A fork that
--     names its parent in previous_ids, on a machine where both are installed,
--     must not walk off with the parent's options -- and this is not a corner
--     case, it is exactly the situation a fork is usually in.
--   * A destination that already has state is never overwritten.  Adoption is
--     for a mod with nothing, not a way to reset one.
--
-- The move is a REPARENT, not a copy: the old key is removed, so a rename
-- cannot leave a second copy behind that a later build might adopt again.

local ModRename = {}

-- The ids a manifest says it used to have.  Validated the same way a real id
-- is, because these end up as table keys and filesystem path components, and
-- the mod's own id is skipped: "I used to be called what I am called" is a
-- typo, and honouring it would be a self-move.
function ModRename.previousIds(manifest)
  if type(manifest) ~= "table" then return nil end
  local raw = manifest.previousIds or manifest.previous_ids
  if type(raw) ~= "table" then return nil end
  local out, seen = {}, {}
  for _, id in ipairs(raw) do
    if type(id) == "string" and id:match("^[%w_%-]+$")
        and id ~= manifest.id and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  return out[1] and out or nil
end

-- The set of ids that are installed right now, which is what "never adopt from
-- a live mod" is checked against.  Accepts a list of manifests or a map keyed
-- by id, because the loader holds one shape and the launcher the other.
function ModRename.installedIds(manifests)
  local taken = {}
  if type(manifests) ~= "table" then return taken end
  for key, entry in pairs(manifests) do
    local id = nil
    if type(entry) == "table" then
      id = entry.id or (entry.manifest and entry.manifest.id)
    end
    if id == nil and type(key) == "string" then id = key end
    if type(id) == "string" and id ~= "" then taken[id] = true end
  end
  return taken
end

-- Move one mod's entry inside one keyed table.  Returns the id it came from,
-- or nil when there was nothing to do -- which is the overwhelmingly common
-- answer and costs one table lookup to reach.
function ModRename.adoptInto(bucket, manifest, taken)
  if type(bucket) ~= "table" or type(manifest) ~= "table" then return nil end
  local id = manifest.id
  if type(id) ~= "string" or id == "" then return nil end
  if bucket[id] ~= nil then return nil end       -- already has state of its own
  local previous = ModRename.previousIds(manifest)
  if not previous then return nil end
  for _, old in ipairs(previous) do
    if bucket[old] ~= nil and not (taken and taken[old]) then
      bucket[id] = bucket[old]
      bucket[old] = nil
      return old
    end
  end
  return nil
end

-- adoptOptions(options, manifests) -> moved
--
-- Both option tables at once, and deliberately NOT as one loop over a merged
-- list: a mod can have an enable entry under the old id and no options, or the
-- other way round, and stopping at the first hit would strand the other.
--
-- Returns true when anything moved, which is the caller's signal to write the
-- options file -- a rename must not make every launcher frame a disk write.
function ModRename.adoptOptions(options, manifests)
  if type(options) ~= "table" or type(manifests) ~= "table" then return false end
  local taken = ModRename.installedIds(manifests)
  local moved = false
  local list = {}
  for _, entry in pairs(manifests) do
    local m = (type(entry) == "table") and (entry.manifest or entry) or nil
    if type(m) == "table" and type(m.id) == "string" then list[#list + 1] = m end
  end
  for _, manifest in ipairs(list) do
    if options.mods
        and ModRename.adoptInto(options.mods, manifest, taken) then
      moved = true
    end
    if options.modOptions
        and ModRename.adoptInto(options.modOptions, manifest, taken) then
      moved = true
    end
  end
  return moved
end

-- The same for a save's per-mod state.  Separate from the options pass because
-- it happens somewhere else entirely -- a save is adopted when a playthrough
-- opens, and there may be several saves, each needing this once.
function ModRename.adoptModData(modData, manifests)
  if type(modData) ~= "table" or type(manifests) ~= "table" then return false end
  local taken = ModRename.installedIds(manifests)
  local moved = false
  for _, entry in pairs(manifests) do
    local m = (type(entry) == "table") and (entry.manifest or entry) or nil
    if type(m) == "table" and type(m.id) == "string" then
      if ModRename.adoptInto(modData, m, taken) then moved = true end
    end
  end
  return moved
end

return ModRename
