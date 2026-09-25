-- What is actually in the item balls and under the ground.
--
-- 591 of the map's events are a pickup -- 329 visible balls and 262 hidden
-- items -- and until now the cache recorded only that they HAD a script.  The
-- item each one holds is knowable, and the two kinds are knowable in
-- completely different ways, which is the whole content of this file.
--
-- A VISIBLE ITEM CARRIES ITS ITEM IN THE SCRIPT.  Script id 7000+n reaches
-- entry n of scripts_visible_items, and every one of those entries is the same
-- three instructions:
--
--     setvarfromvalue 0x8008, <item id>
--     setvarfromvalue 0x8009, <quantity>
--     goto <the shared pick-up-a-ball routine>
--
-- so the item is read out of the script itself.  327 of the file's 328 entries
-- are that shape; the odd one out is the last.
--
-- A HIDDEN ITEM DOES NOT.  All 284 entries of scripts_hidden_items point at
-- ONE offset -- they are literally the same routine 284 times -- and it reads
-- its item out of script variables 0x8000..0x8002 that the engine fills in
-- before starting it (ScriptManager_SetHiddenItem).  The values come from
-- gHiddenItems in the ARM9: 257 rows of
--
--     u16 item, u8 quantity, u8 searchRange, u16 padding(always 0), u16 script
--
-- searched by `script == id - 8000`, NOT indexed by it -- the script numbers
-- are derived from flag ids and are not consecutive, so a row lookup by
-- position is wrong for most of the table.
--
-- Both tables are read from the cartridge; only the fact that they exist comes
-- from pret.  Verified: all 591 pickup events in Sinnoh resolve, and the
-- commonest ones are 32 Rare Candies, 30 Ultra Balls and 20 Star Pieces, which
-- is what Sinnoh is.

local Gen4Pickups = {}

Gen4Pickups.VISIBLE_BASE = 7000
Gen4Pickups.HIDDEN_BASE = 8000

Gen4Pickups.VAR_ITEM = 0x8008
Gen4Pickups.VAR_QUANTITY = 0x8009

Gen4Pickups.ROW_BYTES = 8
Gen4Pickups.MIN_ROWS = 64

local function u8(s, at) return s:byte(at + 1) end
local function u16(s, at)
  local a, b = s:byte(at + 1, at + 2)
  if not b then return nil end
  return a + b * 256
end

-- A row that could be a hidden item.  Deliberately loose on the values and
-- strict on the SHAPE: the padding halfword is the discriminator, because two
-- zero bytes in the middle of every row is not what ordinary code or a string
-- table looks like.  Measured: the run is found at the same address with the
-- item ceiling anywhere from 468 to 65535, so the shape is what identifies it
-- and the ceiling is only a bound.
--
-- THE CEILING MUST BE THE ID SPACE, NOT THE SIZE OF A DATA ARCHIVE.  Passing
-- pl_item_data.narc's member count (446) looks like the careful choice and is
-- wrong: item ids run past it -- the real table holds one of 451 -- so the run
-- breaks in the middle and the finder returns 216 rows instead of 257, losing
-- 41 hidden items with no error anywhere.  The item NAME bank (468) is the id
-- space; a plain large bound is safer still.
local function plausible(data, at, itemCeiling)
  local item, quantity, range, pad, script =
    u16(data, at), u8(data, at + 2), u8(data, at + 3), u16(data, at + 4), u16(data, at + 6)
  if not (item and quantity and range and pad and script) then return false end
  if pad ~= 0 then return false end
  if item < 1 or item >= itemCeiling then return false end
  if quantity < 1 or quantity > 99 then return false end
  if range > 3 then return false end
  if script >= 1024 then return false end
  return true
end

-- hiddenItems(arm9, itemCount) -> { [script] = { item, quantity, range } }, rows, offset
--
-- Found by taking the LONGEST run of plausible rows rather than the first,
-- which is the correction two other finders in this project needed before it.
function Gen4Pickups.hiddenItems(data, itemCount)
  if type(data) ~= "string" then return nil end
  itemCount = itemCount or 65535
  local bestAt, bestRows = nil, 0
  local at = 0
  while at <= #data - Gen4Pickups.ROW_BYTES do
    if plausible(data, at, itemCount) then
      local rows = 0
      while plausible(data, at + rows * Gen4Pickups.ROW_BYTES, itemCount) do rows = rows + 1 end
      if rows > bestRows then bestAt, bestRows = at, rows end
      at = at + rows * Gen4Pickups.ROW_BYTES
    else
      at = at + 4
    end
  end
  if not bestAt or bestRows < Gen4Pickups.MIN_ROWS then return nil end
  local out = {}
  for i = 0, bestRows - 1 do
    local off = bestAt + i * Gen4Pickups.ROW_BYTES
    out[u16(data, off + 6)] = {
      item = u16(data, off),
      quantity = u8(data, off + 2),
      range = u8(data, off + 3),
    }
  end
  return out, bestRows, bestAt
end

-- visibleItems(scriptData, Gen4Script) -> { [entry] = { item, quantity } }
function Gen4Pickups.visibleItems(data, Gen4Script)
  if type(data) ~= "string" or not Gen4Script then return nil end
  local entries = Gen4Script.entries(data)
  if not entries then return nil end
  local out, found = {}, 0
  for index = 1, #entries do
    local item, quantity
    local ok, instructions = pcall(Gen4Script.decode, data, entries[index])
    if ok and instructions then
      for _, instruction in ipairs(instructions) do
        if instruction.name == "setvarfromvalue" and instruction.args then
          local which = tonumber(instruction.args[1])
          local value = tonumber(instruction.args[2])
          if which == Gen4Pickups.VAR_ITEM then item = value
          elseif which == Gen4Pickups.VAR_QUANTITY then quantity = value end
        end
      end
    end
    if item then
      out[index - 1] = { item = item, quantity = quantity or 1 }
      found = found + 1
    end
  end
  return out, found
end

-- resolve(scriptId, visible, hidden) -> { item, quantity, range, kind } or nil
function Gen4Pickups.resolve(scriptId, visible, hidden)
  if type(scriptId) ~= "number" then return nil end
  if scriptId >= Gen4Pickups.VISIBLE_BASE and scriptId < Gen4Pickups.HIDDEN_BASE then
    local row = visible and visible[scriptId - Gen4Pickups.VISIBLE_BASE]
    if not row then return nil end
    return { item = row.item, quantity = row.quantity, kind = "ball" }
  end
  if scriptId >= Gen4Pickups.HIDDEN_BASE and scriptId < 8800 then
    local row = hidden and hidden[scriptId - Gen4Pickups.HIDDEN_BASE]
    if not row then return nil end
    return { item = row.item, quantity = row.quantity, range = row.range, kind = "hidden" }
  end
  return nil
end

return Gen4Pickups
