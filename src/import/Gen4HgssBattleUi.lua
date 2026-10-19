-- HEARTGOLD AND SOULSILVER'S BATTLE INTERFACE: the healthboxes, the touch
-- screen, the cursor, the party balls and gauge, the battle bag and party
-- list -- Platinum's importers run over HGSS's numbered archives.
--
-- The battle code is the same program in both games (pokeheartgold
-- src/battle/battle_hp_bar.c, battle_input.c, battle_cursor.c, party_gauge.c
-- against pokeplatinum's healthbox.c, battle_subscreen.c, cursor_renderer.c,
-- party_gauge.c), reading the same archives under numbers instead of names:
--
--   pl_batt_obj.narc     -> /a/0/0/8   every member the port reads identical
--                                      (healthboxes 186-203, cursor 250-252,
--                                      balls 204-209, gauge 340-342, palettes
--                                      71/72/80/110); HGSS appends 343-345,
--                                      the Bug Contest's net and Sport Ball
--   pl_batt_bg.narc      -> /a/0/0/7   tiles 28 and the backdrop tiles / map
--                                      as Platinum; the subscreen tilemaps
--                                      42-49 are six LOWER (battle_input.c
--                                      112-120, 2167) and every palette from
--                                      171 is four HIGHER (backdrops 0xAC ->
--                                      0xB0, the subscreen 242 -> 246, the
--                                      per-background pairs 0xF3.. -> 0xF7..,
--                                      battle_input.c 1235-1365), the
--                                      Frontier's 340/341 nine higher
--   pl_b_plist_gra.narc  -> /a/0/7/1   identical (asm/overlay_08.s 2194-2253)
--   b_bag_gra.narc       -> /a/0/7/7   identical (overlay_08.s 14108-14163)
--   pl_font.narc         -> /a/0/1/6   one higher from member 4 -- HGSS has a
--                                      fifth glyph file (font.c 19-26)
--   pl_pst_gra.narc      -> /a/0/3/9   the status icons at the same 62-65
--   pl_plist_gra.narc    -> /a/0/2/1   the item / mail icons at the same 18-21
--   pl_winframe.narc     -> /a/0/3/8
--
-- and the move buttons' type palettes sit in overlay 6 (ov06_0221BDD0), not
-- Platinum's 11. So rather than a second copy of every importer, the ROM is
-- handed over behind a view that answers Platinum's paths with HGSS's
-- archives, the shifted ones re-indexed to Platinum's numbering.

local M = {}

local function shiftBg(p)
  if p >= 42 and p <= 49 then return p - 6 end
  if p == 340 or p == 341 then return p + 9 end
  if p >= 169 then return p + 4 end
  return p
end

local function shiftFont(p) return p >= 4 and p + 1 or p end

M.ALIAS = {
  -- Matched to Platinum member by member: all 37 chars/cells/animations
  -- and all 39 palettes are byte-identical. HGSS owns its programs (501)
  -- and particle records (486 moves, 133 balls).
  ["/wazaeffect/we.arc"] = { path = "/a/0/1/0" },
  ["/wazaeffect/effectdata/waza_particle.narc"] = { path = "/a/0/2/9" },
  ["/wazaeffect/effectdata/ball_particle.narc"] = { path = "/a/0/9/5" },
  ["/wazaeffect/effectclact/wechar.narc"] = { path = "/a/0/2/2" },
  ["/wazaeffect/effectclact/wepltt.narc"] = { path = "/a/0/2/3" },
  ["/wazaeffect/effectclact/wecell.narc"] = { path = "/a/0/2/4" },
  ["/wazaeffect/effectclact/wecellanm.narc"] = { path = "/a/0/2/5" },
  ["/battle/graphic/pl_batt_obj.narc"] = { path = "/a/0/0/8" },
  ["/battle/graphic/pl_batt_bg.narc"] = { path = "/a/0/0/7", member = shiftBg },
  ["/battle/graphic/pl_b_plist_gra.narc"] = { path = "/a/0/7/1" },
  ["/battle/graphic/b_bag_gra.narc"] = { path = "/a/0/7/7" },
  ["/graphic/pl_font.narc"] = { path = "/a/0/1/6", member = shiftFont },
  ["/graphic/pl_pst_gra.narc"] = { path = "/a/0/3/9" },
  ["/graphic/pl_plist_gra.narc"] = { path = "/a/0/2/1" },
  ["/graphic/pl_winframe.narc"] = { path = "/a/0/3/8" },
  -- the item icons (NARC_itemtool_itemdata_item_icon, 797 members); the
  -- ARM9 item -> icon table is found and verified exactly as on Platinum
  ["/itemtool/itemdata/item_icon.narc"] = { path = "/a/0/1/8" },
  -- THE SCREENS THAT MAP (scratch_claude/hgss_ui_screens_map.md, member by
  -- member against both ROMs): the naming screen's namein (/a/0/3/1, the same
  -- 19 members, four of them HGSS's own art), the mart's top screen
  -- (/a/0/6/0, members 0-10), and the bag archive's tap ripple (34-37 -> 27-30)
  ["/data/namein.narc"] = { path = "/a/0/3/1" },
  ["/graphic/shop_gra.narc"] = { path = "/a/0/6/0" },
  ["/graphic/pl_bag_gra.narc"] = { path = "/a/0/1/5",
    member = function(p) return (p >= 34 and p <= 37) and p - 7 or p end },
}

-- the party menu's blanked HP bar on an egg: FillBgTilemapRect(..., 0x4B, ...)
-- (party_menu.c 1129-1131) where Platinum fills 0x17
M.EGG_TILE = 0x4B

M.MOVE_BUTTON_OVERLAY = 6

-- The healthbox parts blob (overlay 12's gBattleHpBar_RawGraphicComponents,
-- battle_hp_bar_data.h) is Platinum's 78 tiles in Platinum's order, but its
-- gauges are a row taller: each fill step of the HP ramps lights three pixels
-- a column, the EXP ramp two (measured on the cartridge, overlay 12 +0x35E80).
M.RAMP_ROWS = { hp_green = 3, hp_yellow = 3, hp_red = 3, exp = 2 }

-- The Bug-Catching Contest's subscreen sprites (battle_input.c 4565-4586,
-- 909-934): one sheet on interface/shared.NCLR, the net on row 4 and the
-- Sport Ball on row 5.
M.CONTEST_SETS = {
  { prefix = "contest_net",  char = 343, cell = 344, anim = 345, pal = 72, row = 4, allFrames = true },
  { prefix = "contest_ball", char = 343, cell = 344, anim = 345, pal = 72, row = 5, allFrames = true },
}

-- The archive re-indexed: member p of the result is member `map(p)` of
-- `data`.  Only the allocation table is rewritten; the file image is shared.
function M.remap(data, map)
  local Narc = require("src.import.NarcArchive")
  local arc = Narc.parse(data)
  if not arc then return data end
  local first = arc._entries
  local parts = { data:sub(1, first - 1) }
  for p = 0, arc.count - 1 do
    local h = map(p)
    if not (h >= 0 and h < arc.count) then h = p end
    local at = first + h * 8
    parts[#parts + 1] = data:sub(at, at + 7)
  end
  parts[#parts + 1] = data:sub(first + arc.count * 8)
  return table.concat(parts)
end

-- A view of `rom` that reads Platinum's battle paths out of HGSS.
function M.wrap(rom)
  local cache = {}
  local view = {}
  function view.read(_, path)
    local alias = M.ALIAS[path]
    if not alias then return rom:read(path) end
    if cache[path] == nil then
      local bytes = rom:read(alias.path)
      if bytes and alias.member then bytes = M.remap(bytes, alias.member) end
      cache[path] = bytes or false
    end
    return cache[path] or nil
  end
  return setmetatable(view, { __index = function(_, k)
    local v = rom[k]
    if type(v) == "function" then return function(_, ...) return v(rom, ...) end end
    return v
  end })
end

-- Runs, over HGSS, what Platinum's import runs for the battle screen: the
-- `gen4_graphics` battle pictures (backdrops, healthboxes, parts, digits,
-- subscreen), the move buttons and `gen4_battle_art`. The Platinum-only
-- screens that stage would also walk are left out, and the window frames
-- stay the ones the HGSS frames stage found.
function M.extract(x)
  local Screens = require("src.import.Gen4Screens")
  local UiRes = require("src.import.Gen4UIResources")
  local MoveButtons = require("src.import.Gen4MoveButtons")
  local BattleArt = require("src.import.Gen4BattleArt")
  local Parts = require("src.import.Gen4HealthboxParts")
  -- the HGSS import keys `fonts` to /a/0/1/6 itself; for this run it is
  -- Platinum's name, so the view re-indexes it like the rest
  local PATH = require("src.import.RomExtractorGen4").PATH
  local saved = {
    rom = x.rom, archives = x._archives, plan = Screens.planAll, ui = UiRes.images,
    overlay = MoveButtons.OVERLAY, sets = BattleArt.SETS, ramps = Parts.RAMPS,
    fonts = PATH.fonts, data = BattleArt.data,
  }
  local ramps = {}
  for i, r in ipairs(saved.ramps) do
    ramps[i] = { name = r.name, at = r.at, cells = r.cells, rows = M.RAMP_ROWS[r.name] or r.rows }
  end
  local sets = {}
  for i, s in ipairs(saved.sets) do sets[i] = s end
  for _, s in ipairs(M.CONTEST_SETS) do sets[#sets + 1] = s end

  x.rom, x._archives = M.wrap(saved.rom), {}
  Screens.planAll = function() return {} end
  UiRes.images = function() return {} end
  MoveButtons.OVERLAY = M.MOVE_BUTTON_OVERLAY
  BattleArt.SETS = sets
  Parts.RAMPS = ramps
  PATH.fonts = "/graphic/pl_font.narc"
  -- the contest strip's ink: sub OBJ palette 3 of interface/shared.NCLR
  -- (member 72), the row its TEXT_COLORs index (battle_input.c 1966-1990)
  BattleArt.data = function(rom)
    local out = saved.data(rom)
    local G = require("src.import.Gen4Graphics")
    local Narc = require("src.import.NarcArchive")
    local raw = rom:read(BattleArt.PATH)
    local arc = raw and Narc.parse(raw)
    local b = arc and arc:get(72)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    local pal = b and G.palette(b)
    if pal then
      local r3 = {}
      for i = 0, 15 do
        local c = pal[3 * 16 + i + 1]
        r3[i] = c and { c[1], c[2], c[3] } or { 0, 0, 0 }
      end
      out.subscreenInk = out.subscreenInk or {}
      out.subscreenInk.contest = r3
    end
    return out
  end
  x.extractWindowFrames = function(self) return self._winFrames end

  local Party = require("src.import.Gen4PartyArt")
  local eggTile = Party.EGG_TILE
  Party.EGG_TILE = M.EGG_TILE
  -- the move-animation backgrounds at HGSS's own members (overlay 7's
  -- table, Gen4HgssBattle.EFFECT_BG_MEMBERS), read from /a/0/0/7 directly
  local Bg4 = require("src.import.Gen4Battle")
  local Hgss = require("src.import.Gen4HgssBattle")
  local savedBg = { members = Bg4.EFFECT_BG_MEMBERS, count = Bg4.EFFECT_BG_COUNT,
                    archive = Bg4.EFFECT_BG_ARCHIVE }
  Bg4.EFFECT_BG_MEMBERS, Bg4.EFFECT_BG_COUNT = Hgss.EFFECT_BG_MEMBERS, Hgss.EFFECT_BG_COUNT
  Bg4.EFFECT_BG_ARCHIVE = Hgss.PATH
  local ok, err = pcall(function()
    x:extractGraphics()
    x:moveButtons()
    x:battleArt()
    x:extractMoveAnims()
    if x._moveAnims and x._moveAnims.skipped>0 then
      print(('HGSS move animations: %d programs use unsupported HGSS-only opcodes; generic effects remain for these moves'):format(x._moveAnims.skipped))
    end
    x:extractParticles()
    x:extractCellActors()
    -- the screens that are Platinum's under other numbers
    x:extractNaming()
    x:partyArt()
    local shop = require("src.import.Gen4ShopArt").images(x.rom)
    if shop then
      local index = {}
      for key, image in pairs(shop) do
        index[key] = x:saveImage("shop_art/" .. key, image, { originX = image.originX, originY = image.originY })
      end
      x:write("gen4_shop_art", index)
    end
  end)
  Party.EGG_TILE = eggTile
  Bg4.EFFECT_BG_MEMBERS, Bg4.EFFECT_BG_COUNT = savedBg.members, savedBg.count
  Bg4.EFFECT_BG_ARCHIVE = savedBg.archive

  x.rom, x._archives = saved.rom, saved.archives
  Screens.planAll, UiRes.images = saved.plan, saved.ui
  MoveButtons.OVERLAY, BattleArt.SETS = saved.overlay, saved.sets
  Parts.RAMPS = saved.ramps
  PATH.fonts = saved.fonts
  BattleArt.data = saved.data
  x.extractWindowFrames = nil
  if not ok then return nil, err end
  return true
end

return M
