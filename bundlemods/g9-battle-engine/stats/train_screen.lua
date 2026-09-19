-- ============================================================ TRAIN screen
--
-- g9-battle-engine's own TRAIN screen -- MOVED HERE in round 176 (2026-09-18)
-- from g9-battle-sample, where it had lived since 2026-09-14.  This is its
-- home: it edits THIS mod's modern stats (ModernStats.recalcAll -- the same
-- function stats/ev_yield_on_faint.lua calls) and consults this mod's own
-- move-availability gate (mod.exports.isMoveUsable), and both generations'
-- party submenu is already hooked by engine screens (stats/dev_stats_screen
-- .lua).  A consumer that wants the editor does nothing -- it rides with the
-- engine; a consumer that does NOT can turn the TRAIN SCREEN row OFF.
--
-- Gated behind the "train_screen" Mod Manager row (default ON).  OFF leaves
-- the party submenu exactly as the engine found it.
--
-- ============================================================= TRAIN screen
--
-- 2026-09-20 (round 190), explicit user request: the STATS page was moved onto
-- the SAME enlarged 320x180 native window the MOVES page uses ("fix style to
-- match train's MOVES window design and canvas size and screen size") -- one
-- surface, one raw-pixel coordinate system, one border ring for both pages.
-- The MOVES page was NOT touched.  Same round: the stat column bug (three rows
-- printed "---" because computeAll's key names differ from STAT_ORDER's) was
-- fixed, and two ABILITY / HIDDEN strip buttons were added beside MOVES,
-- buying an ability-slot swap for 5000 or a hidden-ability swap for 7000
-- (hidden always returns to the remembered normal ability, stored on the mon
-- as g9PrevAbility so it survives cache clears and sessions).
--
-- 2026-09-14, explicit user request: a "TRAIN" row in the party submenu, on
-- BOTH generations, that opens a two-screen editor for the selected Pokemon.
-- Modeled on the engine's own Adv.Stats party screen (stats/dev_stats_screen
-- .lua) -- the confirmed-working pattern on both generations: a plain window
-- (Gen 1 192x173, Gen 2 160x144) that never touches Renderer:setUISize, the
-- same ui.party.submenu hook, {id=,label=,onSelect=} rows, and a pcall-guarded
-- update/draw pair that pops the screen instead of raising.
--
--   Screen one -- STATS: IV / EV / Nature / gender.
--     A framed tab strip across the top -- IV, EV, NAT, the <male>/<female>
--     symbols and MOVES -- walked with LEFT/RIGHT; the gender tab prints BOTH
--     symbols as its label with a rule under the one currently set, and the
--     footer's gender box prints that one symbol on its own, so the tab is the
--     menu and the footer is the value; UP/DOWN from it drops to
--     the APPLY button under the table.  Every option on the screen is drawn
--     inside a rectangle rather than as bracketed text, and the option the
--     cursor is on is framed twice (explicit user spec).  The six stats
--     (ModernStats.ORDER) are always listed with their IV, EV and resulting
--     stat in framed rows.  On IV/EV, A enters the rows, LEFT/RIGHT cycles the
--     + / - / 0 / 31 buttons, UP/DOWN walks the six stats and A applies the
--     chosen button; on NAT and the gender tab, LEFT/RIGHT (or A) changes that
--     value directly.  A on MOVES opens screen two.  Every change is committed
--     through the battle engine's
--     OWN ModernStats.recalcAll -- the same function stats/ev_yield_on_faint
--     .lua uses -- with the current damage carried across, so the edited
--     numbers are what g9-battle-engine's combat reads.  A committed mon is
--     flagged (mon.g9TrainEdited) so the NATIVE recomputes re-apply the edit
--     instead of silently undoing it:
--       * Gen 2: src/ui/gen2/PartyMenu.lua calls Mon.refreshStats on EVERY
--         party-menu open and Battle.new does on every battle start, both
--         rebuilding mon.stats from dvs/statExp -- Mon.refreshStats is wrapped
--         so an edited mon's modern stats are re-applied right after.
--       * pokemon.level_up (raised by both generations' own experience code
--         after the level change) re-applies at the new level.
--       * battle.started re-applies for the whole party (Gen 2's Battle.new
--         runs its refresh BEFORE it raises that event).
--     Gen 1 also keeps mon.stats.special complete, mirrored from Spa: the
--     native Stats.ensure rebuilds a stat block from DVs when any of its five
--     Gen 1 keys is missing, which would otherwise quietly undo the edit.
--     All edits live on the mon itself (ivs/evs/nature/gender), so they ride
--     the save like any other field.
--
--   Screen two -- MOVES: Egg, Relearn (level-up) and Tutor moves the species
--     can learn, straight from national_dex's UNFILTERED movepool
--     (statsBySpecies(id).movesFull / .movesByMethod), each costing 5000.
--     Machines are deliberately NOT offered -- neither TMs nor TRs, explicit
--     user spec, so movesByMethod.machine is never read -- and a move the mon
--     already knows is never listed.  A move g9-battle-engine cannot actually
--     run yet (its own isMoveUsable) is filtered out too.  A full moveset asks
--     which slot to forget; an HM slot is refused, exactly like the native
--     move deleter.  Money is read/written through the same Gen2Compat-backed
--     save the rest of this mod uses (save.money on Gen 1, save.player.money
--     on Gold).
return function(mod)
  local ModernStats = mod.exports.ModernStats
  if type(ModernStats) ~= "table" then
    mod.log:warn("g9-battle-engine: TRAIN screen not installed -- "
      .. "ModernStats unavailable")
    return
  end

  local Font = require("src.render.Font")
  local GameVersion = require("src.core.GameVersion")
  -- The generation this boot runs on -- the same answer the engine's own
  -- adv.stats screen reads (GameVersion.generation(GameVersion.get())).
  local gen = 1
  do
    local okGen, value = pcall(function()
      return GameVersion.generation(GameVersion.get())
    end)
    if okGen and (value == 1 or value == 2) then gen = value end
  end

  local STAT_ORDER = ModernStats.ORDER
  local STAT_LABEL = { hp = "HP", atk = "ATK", def = "DEF",
    spa = "SPA", spd = "SPD", spe = "SPE" }
  local NATURES = ModernStats.NATURES or {}
  local MOVE_COST = 5000
  -- Indexed by the CATEGORY the LEFT/RIGHT keys walk (1..3), which is also
  -- the order Screen:buildMoveList reads them in: 1 level-up/relearn, 2 egg,
  -- 3 tutor.  The label must match the list it names -- it previously read
  -- {EGG, RELEARN, TUTOR}, so the header said EGG while the rows below were
  -- level-up moves.
  local MOVE_FIELD_LABELS = { "RELEARN", "EGG", "TUTOR" }
  -- Moves the native move deleter refuses to forget (engine/pokemon/learn.asm
  -- HM_MOVES); a paid slot replacement is held to the same rule.
  local HM_MOVES = {
    CUT = true, FLY = true, SURF = true, STRENGTH = true, FLASH = true,
    WHIRLPOOL = true, WATERFALL = true, DIVE = true,
  }
  -- The Gen 2 party submenu box holds NumMonMenuItems (8) rows; Gen 1's grows
  -- upward with no ceiling.  Same guard the engine's own adv.stats screen uses.
  local NUM_MONMENU_ITEMS = 8

  -- --------------------------------------------------------------- plumbing
  -- national_dex is optional; every lookup below degrades to "no data" rather
  -- than erroring when it is absent, the same contract ModernStats itself uses.
  local function ndExports()
    local nd = mod.find and mod.find("national_dex")
    return nd and nd.exports
  end

  local function defFromData(data, mon)
    local fallback = data and data.pokemon and data.pokemon[mon.species]
    return ModernStats.resolveBase(mon.species, fallback, ndExports())
  end
  local function defFor(game, mon)
    return defFromData(game and game.data, mon)
  end

  local function liveSave()
    local ok, Game = pcall(require, "src.core.Game")
    if ok and type(Game) == "table" then return Game.save end
    return nil
  end
  local function liveData()
    local ok, Game = pcall(require, "src.core.Game")
    if ok and type(Game) == "table" then return Game.data end
    return nil
  end

  -- Gen 2 keeps the wallet on save.player.money; Gen 1 on save.money.  Read the
  -- Gen 2 field FIRST so the Gen 2Compat facade's `save.money` (documented as
  -- absent on Gold) is never touched there.
  local function moneyOf(save)
    if type(save) ~= "table" then return 0 end
    local player = save.player
    if type(player) == "table" and type(player.money) == "number" then
      return player.money
    end
    return tonumber(save.money) or 0
  end
  local function setMoney(save, value)
    if type(save) ~= "table" then return end
    value = math.max(0, math.floor(value or 0))
    local player = save.player
    if type(player) == "table" and player.money ~= nil then
      player.money = value
    else
      save.money = value
    end
  end

  -- Commit an edited mon's modern fields to mon.stats.  Same body as the
  -- engine's own ev_yield_on_faint recompute: carry the missing HP across
  -- rather than healing to full, mirror the split specials into whichever key
  -- names this generation's native code reads, and keep maxHp in step on Gen 2.
  local function applyModern(def, mon)
    if type(mon) ~= "table" then return end
    if type(def) ~= "table" or type(def.baseStats) ~= "table" then return end
    mon.stats = mon.stats or {}
    local oldMax = mon.stats.hp or 1
    local oldHp = math.max(0, math.min(mon.hp or 0, oldMax))
    local missing = math.max(0, oldMax - oldHp)
    ModernStats.recalcAll(def, mon)
    if gen == 2 then
      mon.stats.specialAttack = mon.stats.spa
      mon.stats.specialDefense = mon.stats.spd
      mon.maxHp = mon.stats.hp
    else
      -- Keep Gen 1's five-key stat block complete (and current) so the native
      -- Stats.ensure never treats it as unfinished and rebuilds it from DVs.
      mon.stats.special = mon.stats.spa
    end
    if oldHp <= 0 then
      mon.hp = 0
    else
      mon.hp = math.max(1, mon.stats.hp - missing)
    end
    -- Gender is NOT part of recalcAll, but the native code re-derives it from
    -- the mon's DVs on its own (Gen 2's Mon.refreshStats -> syncIdentity does,
    -- on every party-menu open and battle start), so a natively-refreshed mon
    -- would silently lose the gender the player committed here.  Put the
    -- committed value back whenever there is one (Screen:commit sets it).
    if mon.g9TrainGender ~= nil then mon.gender = mon.g9TrainGender end
    mon.modernStatsInitialized = true
    mon.g9TrainEdited = true
  end

  -- ---------------------------------------------------- change preservation
  -- (1) Gen 2: re-apply after every native refreshStats.
  if gen == 2 then
    local okMon, Mon = pcall(require, "src.battle.gen2.Mon")
    if okMon and type(Mon) == "table"
        and type(Mon.refreshStats) == "function"
        and not Mon.__g9TrainRefreshWrapped then
      Mon.__g9TrainRefreshWrapped = true
      local nativeRefresh = Mon.refreshStats
      Mon.refreshStats = function(mon, data)
        local result = nativeRefresh(mon, data)
        if type(mon) == "table" and mon.g9TrainEdited then
          pcall(applyModern, defFromData(data, mon), mon)
        end
        return result
      end
    end
  end

  -- (2) Either generation: re-apply after a level change (both Experience.lua
  -- and gen2/Mon.lua raise this AFTER writing the new level's stats).
  mod.events:on("pokemon.level_up", function(ev)
    local mon = ev and ev.mon
    if type(mon) ~= "table" or not mon.g9TrainEdited then return end
    local ok, err = pcall(function()
      applyModern(defFromData(liveData(), mon), mon)
    end)
    if not ok then
      mod.log:warn("g9-battle-engine: TRAIN level-up reapply failed: %s",
        tostring(err))
    end
  end)

  -- (3) Either generation: re-apply the whole party at battle start.  Gen 2's
  -- Battle.new refreshes stats BEFORE raising battle.started, so without this
  -- an edited mon would fight with its DV-derived numbers.
  mod.events:on("battle.started", function()
    local ok, err = pcall(function()
      local save = liveSave()
      if type(save) ~= "table" then return end
      local data = liveData()
      for _, mon in ipairs(save.party or {}) do
        if type(mon) == "table" and mon.g9TrainEdited then
          applyModern(defFromData(data, mon), mon)
        end
      end
    end)
    if not ok then
      mod.log:warn("g9-battle-engine: TRAIN battle-start reapply failed: %s",
        tostring(err))
    end
  end)

  -- --------------------------------------------------------------- geometry
  -- ROUND 190 (2026-09-20, explicit user request): the STATS page now uses
  -- the SAME enlarged 320x180 surface the MOVES page does -- "fix style to
  -- match train's MOVES window design and canvas size and screen size".  Both
  -- pages are therefore one native 320x180 window drawn in raw pixels (S = 1),
  -- so a 960x540 window is a whole 3x with no letterbox, and the two screens
  -- read as one continuous design.  The MOVES page's own layout is untouched.
  --
  -- Both generation's surface seams are answered from this one pair -- see
  -- Screen:uiSize (Gen 1) and Screen:drawWidescreen (Gen 2) below.
  local isGen1Boot = (gen == 1)
  local STATS_W, STATS_H = 320, 180
  local MOVE_W, MOVE_H = 320, 180
  -- One raw-pixel coordinate system for both pages now, so SX is identity and
  -- the design constants below ARE screen pixels.
  local S = 1
  local function SX(v) return math.floor(v + 0.5) end
  local function cell(text, x, y)
    Font.draw(text, SX(x), SX(y))
  end

  -- The selection arrow.  It is a font TILE, not a character: charmap.asm $ED
  -- is the filled right arrow both generations' tile sheets carry, and it is
  -- what the engine's own cursors are (src/ui/Theme.lua `cursor`,
  -- src/ui/gen2/Chrome.lua CURSOR, every battle move list).  Drawn by code
  -- deliberately -- a plain ">" has no charmap entry, so under the TTF the
  -- renderer substitutes for single characters it fell through to the bundled
  -- Plain Pixel, which has no ">" glyph either, and the cursor came out as
  -- NOTHING.  That is why the MOVES page showed no arrow at all.
  local CURSOR_CODE = 0xED
  local function cursor(x, y)
    Font.drawCode(CURSOR_CODE, SX(x), SX(y))
  end

  -- Every option on this screen -- tab, button, stat row, nature/gender,
  -- APPLY -- is drawn inside a frame.  `level` 2 adds a second, 1px-inner
  -- frame and is how the cursor is shown: the tile font draws black glyphs on
  -- transparent whatever the colour, so inversion is not available and the
  -- weight of the frame is the only selection cue.
  local function frame(x, y, w, h, level)
    love.graphics.rectangle("line", SX(x), SX(y), SX(w), SX(h))
    if (level or 1) > 1 then
      love.graphics.rectangle("line", SX(x) + 1, SX(y) + 1,
        math.max(0, SX(w) - 2), math.max(0, SX(h) - 2))
    end
  end

  -- A native Game Boy window ring around a whole surface, tiled from the
  -- engine's own border glyphs.  Font.drawBox is the usual way to get this
  -- look, but it takes TILE counts, and the MOVES page's 180-pixel height is
  -- 22.5 tiles -- drawBox would put its bottom row at y=168 and leave a 4px
  -- gap down the sides.  Tiling the ring here is exact at ANY size, and it
  -- lays down the same four corner and two edge glyphs drawBox uses.
  local function drawBorder(w, h)
    local B = Font.BORDER
    if not (B and B.tl and B.tr and B.bl and B.br and B.h and B.v) then
      Font.drawBox(0, 0, w / 8, h / 8)
      return
    end
    Font.drawCode(B.tl, 0, 0)
    Font.drawCode(B.tr, w - 8, 0)
    Font.drawCode(B.bl, 0, h - 8)
    Font.drawCode(B.br, w - 8, h - 8)
    for x = 8, w - 16, 8 do
      Font.drawCode(B.h, x, 0)
      Font.drawCode(B.h, x, h - 8)
    end
    for y = 8, h - 8, 8 do
      Font.drawCode(B.v, 0, y)
      Font.drawCode(B.v, w - 8, y)
    end
  end

  -- <male> and <female> are single font tiles on BOTH generations: codes 239
  -- and 245 (constants/charmap.asm; the yellow ROM manifest carries the same
  -- pair, and the engine's own naming/summary screens print them).  Drawn by
  -- code rather than by the charmap's multi-byte sequence so the symbol is
  -- there whatever a generation's charmap happens to carry.
  local GENDER_CODE = { male = 239, female = 245 }
  local function drawGender(gender, x, y)
    local code = GENDER_CODE[gender]
    if code then Font.drawCode(code, SX(x), SX(y)) end
  end

  -- The gender tab prints BOTH symbols as its label, so the one the mon is
  -- currently set to is marked with a 1px rule along the tile's own baseline.
  -- That is the only pixel row still free inside the tab -- a focused tab's
  -- double frame already owns the rows above and below the tile -- and the
  -- 1px weight is the cue this screen uses for every other selection, since
  -- the tile font draws black on transparent whatever the colour.  An unknown
  -- gender (a mon the engine never gave one) is simply left unmarked.
  local function drawGenderRule(gender, x, y)
    if not GENDER_CODE[gender] then return end
    love.graphics.rectangle("fill", SX(x), SX(y + 8), SX(8), 1)
  end

  local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
  end

  -- --------------------------------------------------------------- the screen
  -- Editing fees.  An IV point costs IV_COST, an EV point EV_COST, and a
  -- nature change a flat NATURE_COST; gender is free.  A fee is charged per
  -- point of difference from the mon's CURRENT (last committed) value, so
  -- moving a value back toward where it started refunds its points.  Nothing
  -- is charged until the screen's APPLY action, which pays the whole total.
  local IV_COST = 200
  local EV_COST = 125
  local NATURE_COST = 2000
  -- Ability swaps are charged immediately (not staged like the stat edits)
  -- because they are one-shot purchases, not an edited value the player can
  -- walk back: a plain slot-1 <-> slot-2 swap is ABILITY_COST, and either
  -- direction of the hidden-ability swap is HIDDEN_COST (explicit user spec).
  local ABILITY_COST = 5000
  local HIDDEN_COST = 7000

  -- Tab indices.  The gender tab carries no text label -- it prints the two
  -- single-tile gender symbols instead -- so it is marked by `gender = true`.
  -- ABILITY and HIDDEN are ACTION entries in the same strip: left/right walks
  -- onto them like any other entry, but A runs a purchase instead of opening
  -- a page (explicit user spec, "both next to moves button").
  local TAB_IV, TAB_EV, TAB_NAT, TAB_GENDER, TAB_MOVES = 1, 2, 3, 4, 5
  local TAB_ABILITY, TAB_HIDDEN = 6, 7
  local TAB_COUNT = 7

  -- The nudge row, one button set per editing page (explicit user spec: the EV
  -- page gets the wide jumps).  An EV point is a fifth of an IV point and a
  -- stock EV runs to 252, so single-point steps are useless there: the EV page
  -- steps in 4s, 12s and 128s with a 0 reset, while the IV page keeps its
  -- single-point +/- and its 0/31 binders.  A button either adds `delta` to the
  -- stat under the cursor or writes `set` outright.  `pad` is the frame
  -- padding around each label and `gap` the space between buttons; the EV row
  -- is seven buttons wide and only just fits the 160-wide window, so it runs
  -- with 1px padding and no gaps (adjacent frames share their edge line, which
  -- reads as one segmented strip).
  local BUTTONS = {
    [TAB_IV] = { pad = nil, gap = 8, buttons = {
      { label = "+", delta = 1 },
      { label = "-", delta = -1 },
      { label = "0", set = 0 },
      { label = "31", set = 31 },
    } },
    [TAB_EV] = { pad = 1, gap = 0, buttons = {
      { label = "4", delta = 4 },
      { label = "-4", delta = -4 },
      { label = "+12", delta = 12 },
      { label = "-12", delta = -12 },
      { label = "+128", delta = 128 },
      { label = "-128", delta = -128 },
      { label = "0", set = 0 },
    } },
  }
  -- The set the given page edits with; the IV set is the fallback for any page
  -- that has no nudge row at all (the tab walks and applyButton both guard on
  -- IV/EV anyway, but the accessor stays total).
  local function buttonsFor(page) return BUTTONS[page] or BUTTONS[TAB_IV] end

  local TABS = {
    { label = "IV" }, { label = "EV" }, { label = "NAT" },
    { gender = true }, { label = "MOVES" },
    { label = "ABILITY" }, { label = "HIDDEN" },
  }

  -- Both pages live in the same 320x180 raw-pixel surface now (round 190).
  -- Each band below is a row of framed options, laid out against the MOVES
  -- page's own bands: RULE1/RULE2 frame the tab strip exactly as MOVES boxes
  -- its header, the footer rule and the two hint lines sit on MOVE_DIV_Y3 /
  -- MOVE_STATUS_Y / MOVE_HINT_Y, and everything in between shares the one
  -- 8px grid.  The COST / APPLY band gets its own strip between the last stat
  -- row (ROW_TOP + 5 * ROW_STEP + ROW_H = 134) and RULE3, so it no longer
  -- prints over the SPE row (round 190 fix -- see the constants below).
  local DESIGN_W = 320
  local HEADER_Y = 12
  local TAB_Y, TAB_H = 30, 16
  local TAB_PAD, TAB_GAP = 3, 3
  local NUDGE_Y, NUDGE_H = 50, 14
  local TABLE_HDR_Y = 66
  local ROW_TOP, ROW_STEP, ROW_H = 74, 10, 10
  local TABLE_X, TABLE_W = 12, 158
  local COL_LABEL, COL_IV, COL_EV, COL_ST = 16, 56, 80, 108
  local PANEL_X = 182
  -- The info panel's own rows, on the same 8px grid as the table beside it.
  local PANEL_ABILITY_Y = 78
  local PANEL_SLOT_Y = 90
  local PANEL_PREV_Y = 102
  local PANEL_SWAP_Y = 116
  local PANEL_HID_Y = 128
  -- The COST text and the framed APPLY button share one band under the table
  -- (the classic layout had them side by side too), clear of the last stat row
  -- and clear of RULE3.
  local APPLY_Y, APPLY_H = 135, 12
  local COST_Y = 136
  local RULE1_Y, RULE2_Y, RULE3_Y = 24, 48, 148
  local STATUS_Y = 152
  local HINT_Y = 162

  -- The MOVES page's own bands in the enlarged 320x180 surface.  Two 16-glyph
  -- columns of nine rows show EIGHTEEN moves at once, from y=48 to y=146.
  -- Everything is inset one 8px border tile (MOVE_PAD), which is the ring
  -- drawBorder lays down.  THIS PAGE IS UNCHANGED -- round 190 only moved the
  -- STATS page onto the same surface; these constants are the reference the
  -- stats layout above was built to match.
  local MOVE_PAD = 12
  local MOVE_COLS = { 12, 164 }
  local MOVE_ROWS_PER_COL = 9
  local VISIBLE_MOVES = MOVE_ROWS_PER_COL * 2
  local MOVE_ROW_TOP, MOVE_ROW_STEP = 48, 11
  local MOVE_NAME_X, MOVE_NAME_MAX = 10, 16
  local MOVE_DIV_Y1, MOVE_DIV_Y2, MOVE_DIV_Y3 = 24, 42, 148
  local MOVE_STATUS_Y, MOVE_HINT_Y = 152, 162

  -- Lay a row of framed labels out left-to-right from `x0` (default the window
  -- padding), or centred when `x0` is nil: each option is its own text width
  -- plus `pad` either side, with `gap` between them.  `pad` defaults to
  -- TAB_PAD.
  local function layoutRow(labels, gap, pad, x0)
    pad = pad or TAB_PAD
    local widths, total = {}, 0
    for i, label in ipairs(labels) do
      widths[i] = label * 8 + 2 * pad
      total = total + widths[i]
      if i > 1 then total = total + gap end
    end
    local xs = {}
    local x = x0 or math.floor((DESIGN_W - total) / 2 + 0.5)
    for i = 1, #labels do
      xs[i] = x
      x = x + widths[i] + gap
    end
    return xs, widths
  end

  -- Measure and place each page's nudge row once, up front, left-anchored at
  -- the window padding like the tab strip.
  for _, set in pairs(BUTTONS) do
    local glyphs = {}
    for i, button in ipairs(set.buttons) do glyphs[i] = #button.label end
    set.x, set.w = layoutRow(glyphs, set.gap, set.pad, MOVE_PAD)
  end

  -- The tab strip mixes text tabs and the symbol tab, so measure by glyphs.
  local TAB_GLYPHS = {}
  for i, tab in ipairs(TABS) do
    TAB_GLYPHS[i] = tab.gender and 2 or #tab.label
  end
  local TAB_X, TAB_W = layoutRow(TAB_GLYPHS, TAB_GAP, TAB_PAD, MOVE_PAD)

  local Screen = {}
  Screen.__index = Screen
  Screen.isOpaque = true
  Screen.screenId = "G9Train"

  -- The window this screen asks the engine for.  Gen 1's Game:draw reads it
  -- every frame before the draw loop and sizes the canvas from it, so
  -- switching modes resizes the surface: the MOVES page is the enlarged one,
  -- the STATS page its classic window.
  --
  -- Gen 2 has NO such seam -- src/core/Game2.lua composes the window itself
  -- and never calls Renderer:setUISize or reads a state's uiSize at all (the
  -- only reason a 240x216 MOVES page came out clipped to 160x144 on Gold,
  -- with the list cut mid-name and the hints off the bottom edge).  A screen
  -- wider than 160x144 on Gen 2 therefore has to supply that generation's own
  -- contract instead: drawsWidescreen() + drawWidescreen(winW, winH) +
  -- panelSize(), exactly as src/ui/gen2/BattleState.lua, PartyMenu and the
  -- WideBattle scene do.  Both seams below answer from the SAME sizes, so one
  -- layout serves both generations.
  function Screen:uiSize()
    if self.mode == "moves" then return MOVE_W, MOVE_H end
    return STATS_W, STATS_H
  end

  -- A wide owner: Gen 1's Game:draw then sizes the canvas to uiSize() above
  -- wherever this screen sits in the stack and draws it at the surface origin
  -- instead of shifting it by the classic-UI offset (which for a 320-wide
  -- surface would be 80px).  Also makes the screen hold its surface while a
  -- prompt is pushed over it.  Never touches the Renderer itself -- see draw.
  function Screen:isWideBattleLayout() return true end

  -- Fill the letterbox around the surface with the window's own paper rather
  -- than flat black, so a window that is not an exact multiple reads as one
  -- continuous screen (the same opt-in the engine's battle screens use).
  Screen.letterboxWhite = true

  -- Gen 2's panel contract: the surface this screen owns, and the whole-pixel
  -- window scale it should be blitted at.
  function Screen:panelSize()
    if self.mode == "moves" then return MOVE_W, MOVE_H end
    return STATS_W, STATS_H
  end

  function Screen:battlePanelScale(winW, winH) return self:panelScale(winW, winH) end

  -- Whole window pixels per surface pixel, so the 8px grid every frame and
  -- glyph sits on stays aligned.  Chrome owns the playfield/skin maths, so it
  -- is preferred; the plain floor is the same answer without a skin.
  function Screen:panelScale(winW, winH)
    local w, h = self:panelSize()
    local ok, Chrome = pcall(require, "src.ui.gen2.Chrome")
    if ok and type(Chrome) == "table" and Chrome.fitScaleFor then
      local okScale, scale = pcall(Chrome.fitScaleFor, winW, winH, w / 8, h / 8)
      if okScale and type(scale) == "number" and scale >= 1 then return scale end
    end
    if not (winW > 0 and winH > 0) then return 1 end
    return math.max(1, math.floor(math.min(winW / w, winH / h)))
  end

  -- Gen 2 dispatch flag: drawWidescreen paints the whole window for us.
  function Screen:drawsWidescreen() return true end

  -- Gen 2's draw entry.  paint the surround, then draw the surface at the
  -- whole-pixel scale into it.  draw() itself is always in surface pixels, so
  -- this is the only place the window scale lives on Gold.
  function Screen:drawWidescreen(winW, winH)
    local G = love.graphics
    local w, h = self:panelSize()
    local scale = self:panelScale(winW, winH)
    local ox, oy = 0, 0
    local ok, Chrome = pcall(require, "src.ui.gen2.Chrome")
    if ok and type(Chrome) == "table" and Chrome.letterbox then
      pcall(Chrome.letterbox, winW, winH, 1, 1, 1)
      local okO, x, y = pcall(Chrome.fitOriginFor, winW, winH, scale, w / 8,
        h / 8)
      if okO and type(x) == "number" then ox, oy = x, y end
    else
      G.setColor(1, 1, 1, 1)
      G.rectangle("fill", 0, 0, winW, winH)
      ox = math.floor((winW - w * scale) / 2 + 0.5)
      oy = math.floor((winH - h * scale) / 2 + 0.5)
    end
    G.push("all")
    G.translate(ox, oy)
    G.scale(scale, scale)
    self:draw()
    G.pop()
    G.setColor(1, 1, 1, 1)
  end

  local function natureIndex(mon)
    local nature = mon and mon.nature
    for i, name in ipairs(NATURES) do
      if name == nature then return i end
    end
    return nil
  end

  function Screen.new(game, mon)
    local def = defFor(game, mon)
    -- Idempotent top-ups, same as the engine's own adv.stats screen: a mon
    -- that has never been through a battle still shows a real nature/gender.
    pcall(ModernStats.generateNature, mon)
    pcall(ModernStats.generateGender, mon)
    if def then pcall(ModernStats.ensure, def, mon) end

    local self = setmetatable({
      game = game, mon = mon, def = def,
      mode = "stats", focus = "tabs", page = TAB_IV, row = 1, col = 1,
      nature = mon.nature, gender = mon.gender,
      baseNature = mon.nature, baseGender = mon.gender,
      category = 1, moveIndex = 1, moveList = {},
      pending = nil, pickingSlot = false, slotIndex = 1,
      status = "", broken = false, abilityConfirm = nil,
      ivs = {}, evs = {}, baseIvs = {}, baseEvs = {},
    }, Screen)
    -- Ability bookkeeping for the ABILITY / HIDDEN strip entries.  The
    -- species' real slots come straight from national_dex (via the same
    -- resolvers ModernStats uses); a mon that has never had an ability
    -- generated gets one now, exactly like nature/gender above, so the swap
    -- buttons always have a well-defined starting point.
    local nd = ndExports()
    self.nd = nd
    self.regularAbilities = ModernStats.resolveAbilities(mon.species, nd)
    self.hiddenAbility = ModernStats.resolveHiddenAbility(mon.species, nd)
    pcall(ModernStats.generateAbility, mon, self.regularAbilities)
    for _, key in ipairs(STAT_ORDER) do
      self.ivs[key] = clamp(tonumber(mon.ivs and mon.ivs[key]) or 0, 0, 31)
      self.evs[key] = clamp(tonumber(mon.evs and mon.evs[key]) or 0, 0, 252)
    end
    for _, key in ipairs(STAT_ORDER) do
      self.baseIvs[key] = self.ivs[key]
      self.baseEvs[key] = self.evs[key]
    end
    return self
  end

  function Screen:evTotal()
    local total = 0
    for _, key in ipairs(STAT_ORDER) do total = total + (self.evs[key] or 0) end
    return total
  end

  -- How many rows of stats the current tab edits: the six stats on IV and EV,
  -- and a single value on the NAT and gender tabs (whose value is drawn in
  -- the footer rather than the table).  APPLY is no longer a row of its own
  -- -- it is a focus of the whole screen (explicit user spec).
  function Screen:statRowCount()
    return (self.page == TAB_IV or self.page == TAB_EV) and #STAT_ORDER or 1
  end

  -- What the STAGED edits would cost: IV_COST per IV point changed plus
  -- EV_COST per EV point changed -- each counted from the mon's last
  -- committed value, so an undone edit costs nothing again -- plus a flat
  -- NATURE_COST when the nature differs.  Gender is free.
  function Screen:pendingCost()
    local cost = 0
    for _, key in ipairs(STAT_ORDER) do
      cost = cost + IV_COST
        * math.abs((self.ivs[key] or 0) - (self.baseIvs[key] or 0))
      cost = cost + EV_COST
        * math.abs((self.evs[key] or 0) - (self.baseEvs[key] or 0))
    end
    if self.nature ~= self.baseNature then cost = cost + NATURE_COST end
    return cost
  end

  function Screen:hasChanges()
    if self:pendingCost() > 0 then return true end
    return (self.gender or "") ~= (self.baseGender or "")
  end

  -- The live preview of the six computed stats for the working copy -- the pure
  -- ModernStats.computeAll, so nothing on the mon is touched until commit.
  -- ROUND 190 FIX: computeAll answers in its OWN key convention
  -- (hp/attack/defense/speed/spa/spd), while this screen reads STAT_ORDER
  -- (hp/atk/def/spa/spd/spe).  The old body handed computeAll's table straight
  -- to drawTable, so preview.atk / preview.def / preview.spe were nil and
  -- those three rows printed "---" -- the exact "stat column shows ---" bug
  -- the user reported.  Remap here so every row gets its real modern value
  -- (base + IV + EV + level + nature, the standard Gen 3+ formula).
  function Screen:preview()
    if not (self.def and type(self.def.baseStats) == "table") then return nil end
    local c = ModernStats.computeAll(self.def.baseStats, self.ivs, self.evs,
      self.mon.level, self.nature)
    return {
      hp = c.hp, atk = c.attack, def = c.defense,
      spa = c.spa, spd = c.spd, spe = c.speed,
    }
  end

  -- Write the working copy onto the mon and recompute through the engine's own
  -- recalcAll.  Only the APPLY action calls this: every button and page just
  -- stages the working copy, so an unaffordable purchase leaves the mon
  -- exactly as it was.
  function Screen:commit()
    local mon = self.mon
    mon.ivs = mon.ivs or {}
    mon.evs = mon.evs or {}
    for _, key in ipairs(STAT_ORDER) do
      mon.ivs[key] = self.ivs[key] or 0
      mon.evs[key] = self.evs[key] or 0
    end
    if self.nature ~= nil then mon.nature = self.nature end
    if self.gender ~= nil then
      mon.gender = self.gender
      -- Remember the committed gender so applyModern can put it back after a
      -- native refreshStats re-derives it from the mon's DVs (see applyModern).
      mon.g9TrainGender = self.gender
    end
    applyModern(self.def, mon)
  end

  function Screen:applyButton()
    if self.page ~= TAB_IV and self.page ~= TAB_EV then return end
    if self.row > #STAT_ORDER then return end
    local store = (self.page == TAB_IV) and self.ivs or self.evs
    local key = STAT_ORDER[self.row]
    local button = buttonsFor(self.page).buttons[self.col]
    if not button then return end
    local value
    if button.set ~= nil then
      value = button.set
    else
      value = (store[key] or 0) + button.delta
    end
    if self.page == TAB_IV then
      store[key] = clamp(value, 0, 31)
    else
      -- Real EV rules: 252 per stat, 510 across all six.
      local others = self:evTotal() - (store[key] or 0)
      store[key] = clamp(math.min(clamp(value, 0, 252), 510 - others), 0, 252)
    end
    self.status = ""
  end

  function Screen:cycleNature(step)
    if #NATURES == 0 then return end
    local index = natureIndex(self) or 0
    index = ((index - 1 + step) % #NATURES) + 1
    self.nature = NATURES[index]
    self.status = ""
  end

  function Screen:toggleGender()
    self.gender = (self.gender == "female") and "male" or "female"
    self.status = ""
  end

  -- Charge the staged total and write the working copy onto the mon.  An
  -- unaffordable total changes nothing at all (no partial spend, no partial
  -- commit); a successful one moves the baseline forward, so the cost reads 0
  -- again and the next edits are priced from the mon's new values.
  function Screen:applyAll()
    if not self:hasChanges() then self.status = "NO CHANGE"; return end
    local cost = self:pendingCost()
    local save = liveSave()
    if moneyOf(save) < cost then
      self.status = string.format("NEED %d", cost)
      return
    end
    if cost > 0 then setMoney(save, moneyOf(save) - cost) end
    self:commit()
    for _, key in ipairs(STAT_ORDER) do
      self.baseIvs[key] = self.ivs[key]
      self.baseEvs[key] = self.evs[key]
    end
    self.baseNature = self.nature
    self.baseGender = self.gender
    self.status = cost > 0 and string.format("APPLIED -%d", cost) or "APPLIED"
  end

  -- ------------------------------------------------------- ability swaps
  -- The ABILITY strip entry swaps slot 1 <-> slot 2 (real Ability Capsule
  -- behaviour: it NEVER touches a mon currently on its hidden ability).
  -- HIDDEN toggles between the current normal ability and the species' hidden
  -- one; leaving hidden returns to the PREVIOUS normal ability, remembered on
  -- the mon as g9PrevAbility so it survives native refreshes, a cache clear,
  -- and a full session -- mon fields ride the save like any other (explicit
  -- user spec).  Both charge immediately and refund nothing.
  --
  -- Which slot the mon is currently on: 1/2 for a regular ability, 3 for the
  -- hidden one, nil when the current name matches neither (an ability from a
  -- provider that isn't in the species' slot list) -- the swaps below all
  -- guard on that, so an unrecognised ability simply can't be swapped.
  function Screen:abilitySlot()
    local mon = self.mon
    if self.hiddenAbility and mon and mon.ability == self.hiddenAbility then
      return 3
    end
    for i, name in ipairs(self.regularAbilities or {}) do
      if mon and name == mon.ability then return i end
    end
    return nil
  end

  -- The normal ability to fall back to when leaving the hidden one: the mon's
  -- remembered g9PrevAbility when that is still a real regular slot for this
  -- species, else slot 1.  nil when the species has no regular ability at all.
  function Screen:previousNormalAbility()
    local prev = self.mon and self.mon.g9PrevAbility
    for _, name in ipairs(self.regularAbilities or {}) do
      if name == prev then return prev end
    end
    return (self.regularAbilities or {})[1]
  end

  -- What an ABILITY / HIDDEN press would do, or a status explaining why it
  -- cannot happen.  Kept separate from the purchase itself so the confirm
  -- prompt can show the real destination and price.
  function Screen:abilitySwapInfo(kind)
    local slot = self:abilitySlot()
    if kind == "regular" then
      local list = self.regularAbilities or {}
      local a, b = list[1], list[2]
      if not (a and b) then return nil, "NO ALT ABILITY" end
      if slot ~= 1 and slot ~= 2 then return nil, "ON HIDDEN" end
      if slot == 1 then return { to = b, cost = ABILITY_COST }, nil end
      return { to = a, cost = ABILITY_COST }, nil
    end
    if slot == 3 then
      local prev = self:previousNormalAbility()
      if not prev then return nil, "NO ABILITY" end
      return { to = prev, cost = HIDDEN_COST }, nil
    end
    if not self.hiddenAbility then return nil, "NO HIDDEN" end
    return { to = self.hiddenAbility, cost = HIDDEN_COST }, nil
  end

  -- A opens the confirm prompt; A on the prompt buys, B backs out.  Nothing is
  -- charged until the buy, so an accidental brush of the strip is free.
  function Screen:requestAbility(kind)
    local info, why = self:abilitySwapInfo(kind)
    if not info then self.status = why or "N/A"; return end
    self.abilityConfirm = kind
    self.status = ""
  end

  function Screen:buyAbility(kind)
    local info, why = self:abilitySwapInfo(kind)
    if not info then self.status = why or "N/A"; return end
    local save = liveSave()
    if moneyOf(save) < info.cost then
      self.status = string.format("NEED %d", info.cost)
      return
    end
    setMoney(save, moneyOf(save) - info.cost)
    local mon = self.mon
    if kind == "hidden" and self:abilitySlot() ~= 3 then
      -- Entering the hidden ability: remember the normal one we came from, so
      -- a later HIDDEN press can put it back (explicit user spec).
      mon.g9PrevAbility = mon.ability
    end
    mon.ability = info.to
    mon.g9AbilityEdited = true
    self.status = string.format("%s -%d", info.to, info.cost)
  end

  function Screen:updateAbilityConfirm(input)
    if input:wasPressed("a") then
      local kind = self.abilityConfirm
      self.abilityConfirm = nil
      self:buyAbility(kind)
    elseif input:wasPressed("b") then
      self.abilityConfirm = nil
      self.status = "CANCELLED"
    end
  end

  -- ------------------------------------------------------------ move pool
  local movePoolCache = {}
  function Screen:buildMoveList()
    self.moveList = {}
    self.moveHint = nil
    local nd = ndExports()
    if not (nd and type(nd.statsBySpecies) == "function") then
      self.moveHint = "NEEDS NATIONAL DEX"
      return
    end
    local ok, rec = pcall(nd.statsBySpecies, self.mon.species)
    if not (ok and type(rec) == "table") then
      self.moveHint = "NO DEX DATA"
      return
    end
    self.mon.moves = self.mon.moves or {}
    local known = {}
    for _, move in ipairs(self.mon.moves) do
      if move and move.id then known[move.id] = true end
    end
    local data = self.game and self.game.data
    local seen = {}
    local function consider(moveId)
      if type(moveId) ~= "string" or moveId == "" then return end
      if seen[moveId] or known[moveId] then return end
      local moveDef = data and data.moves and data.moves[moveId]
      if not moveDef then return end
      -- The engine's own "can this actually be run yet" gate, when exported.
      if mod.exports and type(mod.exports.isMoveUsable) == "function" then
        local okCall, usable = pcall(mod.exports.isMoveUsable, moveId)
        if okCall and usable == false then return end
      end
      seen[moveId] = true
      self.moveList[#self.moveList + 1] = {
        id = moveId, name = moveDef.name or moveId,
      }
    end
    if self.category == 1 then
      -- Relearn: level-up moves at or below the mon's current level.
      for _, entry in ipairs(rec.movesFull or {}) do
        if (entry.level or 1) <= (self.mon.level or 1) then
          consider(entry.move)
        end
      end
    elseif self.category == 2 then
      for _, entry in ipairs((rec.movesByMethod or {}).egg or {}) do
        consider(entry.move)
      end
    else
      for _, entry in ipairs((rec.movesByMethod or {}).tutor or {}) do
        consider(entry.move)
      end
    end
    table.sort(self.moveList, function(a, b) return a.name < b.name end)
    if self.moveIndex > #self.moveList then
      self.moveIndex = math.max(1, #self.moveList)
    end
  end

  function Screen:chooseMove()
    local entry = self.moveList[self.moveIndex]
    self.status = ""
    if not entry then self.status = "NO MOVE"; return end
    if moneyOf(liveSave()) < MOVE_COST then self.status = "NEED 5000"; return end
    local moves = self.mon.moves or {}
    if #moves < 4 then
      self.pending = { entry = entry, slot = #moves + 1 }
    else
      self.pickingSlot = true
      self.slotIndex = 1
    end
  end

  function Screen:writeMove(entry, slot)
    local mon = self.mon
    mon.moves = mon.moves or {}
    local data = self.game and self.game.data
    local moveDef = data and data.moves and data.moves[entry.id]
    local pp = (moveDef and moveDef.pp) or 0
    local newEntry = { id = entry.id, pp = pp }
    -- Gen 2's move records carry maxPp; Gen 1's do not (Mon.learnMove vs
    -- BattleState:learnMove).
    if gen == 2 then newEntry.maxPp = pp end
    mon.moves[slot] = newEntry
    local ok, Runtime = pcall(require, "src.mods.Runtime")
    if ok and type(Runtime) == "table" and type(Runtime.emit) == "function" then
      pcall(Runtime.emit, "pokemon.move_learned",
        { mon = mon, moveId = entry.id })
    end
  end

  function Screen:doTeach()
    local pending = self.pending
    self.pending = nil
    if not pending then return end
    local save = liveSave()
    if moneyOf(save) < MOVE_COST then self.status = "NEED 5000"; return end
    local old = (self.mon.moves or {})[pending.slot]
    if old and HM_MOVES[old.id] then self.status = "CAN'T FORGET HM"; return end
    setMoney(save, moneyOf(save) - MOVE_COST)
    self:writeMove(pending.entry, pending.slot)
    self.status = "LEARNED " .. pending.entry.name
    self:buildMoveList()
  end

  -- --------------------------------------------------------------- input
  local function safeCall(self, label, fn)
    local ok, err = pcall(fn)
    if not ok then
      mod.log:warn("g9-battle-engine: train_screen: %s errored, closing (%s)",
        label, tostring(err))
      self.broken = true
    end
  end

  -- Three focuses, moved between by the D-pad (explicit user spec):
  --   "tabs"  -- the framed tab strip along the top.  LEFT/RIGHT walks the
  --              five tabs; UP/DOWN drops to APPLY; A enters the tab's rows
  --              (or, on MOVES, opens screen two).
  --   "rows"  -- the tab's own rows.  On IV/EV: LEFT/RIGHT cycles that page's
  --              nudge buttons (the IV set: + / - / 0 / 31; the EV set: 4 / -4
  --              / +12 / -12 / +128 / -128 / 0), UP/DOWN walks the six stats,
  --              A runs the button.  On NAT and the gender tab there is a
  --              single value, so LEFT/RIGHT (or A) changes it and UP/DOWN goes
  --              back up to APPLY.
  --   "apply" -- the APPLY button.  A buys the staged edits, UP/DOWN returns
  --              to the tab strip.
  function Screen:updateStats(input)
    if self.focus == "apply" then
      if input:wasPressed("a") then
        self:applyAll()
      elseif input:wasPressed("up") or input:wasPressed("down") then
        self.focus = "tabs"
      end
      return
    end

    if self.focus == "tabs" then
      if input:wasPressed("left") then
        self.page = ((self.page - 2) % TAB_COUNT) + 1
        self.row = 1
        self.col = 1
        self.status = ""
      elseif input:wasPressed("right") then
        self.page = (self.page % TAB_COUNT) + 1
        self.row = 1
        self.col = 1
        self.status = ""
      elseif input:wasPressed("up") or input:wasPressed("down") then
        self.focus = "apply"
      elseif input:wasPressed("a") then
        if self.page == TAB_MOVES then
          self.mode = "moves"
          self:buildMoveList()
          self.moveIndex = 1
        elseif self.page == TAB_ABILITY then
          self:requestAbility("regular")
        elseif self.page == TAB_HIDDEN then
          self:requestAbility("hidden")
        else
          self.focus = "rows"
          self.row = 1
        end
      end
      return
    end

    -- focus == "rows"
    if self.page == TAB_IV or self.page == TAB_EV then
      if input:wasPressed("up") then
        self.row = ((self.row - 2) % #STAT_ORDER) + 1
      elseif input:wasPressed("down") then
        self.row = (self.row % #STAT_ORDER) + 1
      elseif input:wasPressed("left") or input:wasPressed("right") then
        local step = input:wasPressed("right") and 1 or -1
        self.col = ((self.col - 1 + step) % #buttonsFor(self.page).buttons) + 1
      elseif input:wasPressed("a") then
        self:applyButton()
      end
      return
    end

    if input:wasPressed("left") or input:wasPressed("right") then
      local step = input:wasPressed("right") and 1 or -1
      if self.page == TAB_NAT then
        self:cycleNature(step)
      else
        self:toggleGender()
      end
    elseif input:wasPressed("up") or input:wasPressed("down") then
      self.focus = "apply"
    elseif input:wasPressed("a") then
      if self.page == TAB_NAT then
        self:cycleNature(1)
      else
        self:toggleGender()
      end
    end
  end

  function Screen:updateMoves(input)
    if input:wasPressed("left") then
      self.category = ((self.category - 2) % 3) + 1
      self:buildMoveList()
    elseif input:wasPressed("right") then
      self.category = (self.category % 3) + 1
      self:buildMoveList()
    elseif input:wasPressed("up") then
      if #self.moveList > 0 then
        self.moveIndex = ((self.moveIndex - 2) % #self.moveList) + 1
      end
    elseif input:wasPressed("down") then
      if #self.moveList > 0 then
        self.moveIndex = (self.moveIndex % #self.moveList) + 1
      end
    elseif input:wasPressed("a") then
      self:chooseMove()
    end
  end

  function Screen:updateSlotPicker(input)
    local moves = self.mon.moves or {}
    local count = math.max(1, #moves)
    if input:wasPressed("up") then
      self.slotIndex = ((self.slotIndex - 2) % count) + 1
    elseif input:wasPressed("down") then
      self.slotIndex = (self.slotIndex % count) + 1
    elseif input:wasPressed("b") then
      self.pickingSlot = false
    elseif input:wasPressed("a") then
      local old = moves[self.slotIndex]
      self.pickingSlot = false
      if old and HM_MOVES[old.id] then
        self.status = "CAN'T FORGET HM"
        return
      end
      self.pending = { entry = self.moveList[self.moveIndex],
        slot = self.slotIndex }
    end
  end

  function Screen:updateConfirm(input)
    if input:wasPressed("a") then
      self:doTeach()
    elseif input:wasPressed("b") then
      self.pending = nil
      self.status = "CANCELLED"
    end
  end

  function Screen:update(dt)
    if self.broken then
      if self.game and self.game.stack then self.game.stack:pop() end
      return
    end
    safeCall(self, "update", function()
      local input = self.game.input
      if not input then return end
      if self.pending then self:updateConfirm(input); return end
      if self.abilityConfirm then self:updateAbilityConfirm(input); return end
      if self.pickingSlot then self:updateSlotPicker(input); return end
      if input:wasPressed("start") then
        self.status = ""
        if self.mode == "stats" then
          self.mode = "moves"
          self.page = TAB_MOVES
          self:buildMoveList()
          self.moveIndex = 1
        else
          self.mode = "stats"
          self.page = TAB_MOVES
          self.focus = "tabs"
        end
        return
      end
      -- B steps back one level at a time: a row/APPLY cursor returns to the
      -- tab strip, the moves screen returns to the stats screen, and only a
      -- B on the tab strip itself leaves the TRAIN screen.
      if input:wasPressed("b") then
        if self.mode == "moves" then
          self.mode = "stats"
          self.page = TAB_MOVES
          self.focus = "tabs"
          self.status = ""
        elseif self.focus ~= "tabs" then
          self.focus = "tabs"
        else
          self.game.stack:pop()
        end
        return
      end
      if self.mode == "stats" then
        self:updateStats(input)
      else
        self:updateMoves(input)
      end
    end)
  end

  -- --------------------------------------------------------------- drawing
  -- The tab / action strip: framed options, the current one framed twice.  The
  -- gender entry carries no text -- it prints the two single-tile symbols as
  -- its label, with a rule under whichever one the mon is currently set to.
  -- The last two entries, ABILITY and HIDDEN, are purchases rather than pages
  -- (A opens their confirm prompt); they sit right after MOVES, matching the
  -- user's "both next to moves button".
  function Screen:drawTabs()
    for i, tab in ipairs(TABS) do
      local level = (self.focus == "tabs" and self.page == i) and 2 or 1
      frame(TAB_X[i], TAB_Y, TAB_W[i], TAB_H, level)
      local tx, ty = TAB_X[i] + TAB_PAD, TAB_Y + 4
      if tab.gender then
        drawGender("male", tx, ty)
        drawGender("female", tx + 8, ty)
        local current = (self.gender == "female") and tx + 8 or tx
        drawGenderRule(self.gender, current, ty)
      else
        Font.draw(tab.label, SX(tx), SX(ty))
      end
    end
  end

  -- The nudge row shared by the editing pages: the IV / EV button sets, or --
  -- on NAT and the gender page -- the single framed value LEFT/RIGHT cycles.
  function Screen:drawSetRow()
    if self.page == TAB_IV or self.page == TAB_EV then
      local set = buttonsFor(self.page)
      for i, button in ipairs(set.buttons) do
        local level = (self.focus == "rows" and self.col == i) and 2 or 1
        frame(set.x[i], NUDGE_Y, set.w[i], NUDGE_H, level)
        Font.draw(button.label, SX(set.x[i] + (set.pad or TAB_PAD)),
          SX(NUDGE_Y + 3))
      end
    elseif self.page == TAB_NAT then
      local label = tostring(self.nature or "----")
      local level = (self.focus == "rows") and 2 or 1
      frame(TABLE_X, NUDGE_Y, #label * 8 + 2 * TAB_PAD, NUDGE_H, level)
      Font.draw(label, SX(TABLE_X + TAB_PAD), SX(NUDGE_Y + 3))
    elseif self.page == TAB_GENDER then
      local level = (self.focus == "rows") and 2 or 1
      frame(TABLE_X, NUDGE_Y, 16 + 2 * TAB_PAD, NUDGE_H, level)
      if GENDER_CODE[self.gender] then
        drawGender(self.gender, TABLE_X + TAB_PAD, NUDGE_Y + 3)
      else
        drawGender("male", TABLE_X + TAB_PAD, NUDGE_Y + 3)
        drawGender("female", TABLE_X + TAB_PAD + 8, NUDGE_Y + 3)
      end
    end
  end

  -- The six stats, always visible whatever page is current: the IV column, the
  -- EV column and the resulting modern stat (base + IV + EV + level + nature).
  -- Every row is framed; the row the cursor is on is framed twice.
  function Screen:drawTable(preview, editable)
    cell("STAT", COL_LABEL, TABLE_HDR_Y)
    cell("IV", COL_IV, TABLE_HDR_Y)
    cell("EV", COL_EV, TABLE_HDR_Y)
    cell("CUR", COL_ST, TABLE_HDR_Y)
    for i, key in ipairs(STAT_ORDER) do
      local y = ROW_TOP + (i - 1) * ROW_STEP
      local level = (editable and self.focus == "rows" and self.row == i)
        and 2 or 1
      frame(TABLE_X, y, TABLE_W, ROW_H, level)
      cell(STAT_LABEL[key], COL_LABEL, y + 1)
      cell(string.format("%2d", self.ivs[key] or 0), COL_IV, y + 1)
      cell(string.format("%3d", self.evs[key] or 0), COL_EV, y + 1)
      local stat = preview and preview[key]
      cell(stat and string.format("%3d", stat) or "---", COL_ST, y + 1)
    end
  end

  -- The right-hand info panel: the mon's current ability, which slot it is in
  -- (SLOT 1 / SLOT 2 / HIDDEN), the remembered normal ability a HIDDEN press
  -- would return to, and the two swap prices.
  function Screen:drawPanel()
    local mon = self.mon
    local slot = self:abilitySlot()
    cell("ABILITY", PANEL_X, TABLE_HDR_Y)
    cell(string.sub(tostring(mon.ability or "----"), 1, 14), PANEL_X, PANEL_ABILITY_Y)
    local slotLabel = (slot == 3) and "HIDDEN"
      or ("SLOT " .. tostring(slot or "?"))
    cell(slotLabel, PANEL_X, PANEL_SLOT_Y)
    cell("PREV " .. string.sub(tostring(mon.g9PrevAbility or "----"), 1, 9),
      PANEL_X, PANEL_PREV_Y)
    cell(string.format("SWAP %d", ABILITY_COST), PANEL_X, PANEL_SWAP_Y)
    cell(string.format("HID  %d", HIDDEN_COST), PANEL_X, PANEL_HID_Y)
  end

  function Screen:drawHint()
    local hint
    if self.abilityConfirm then
      hint = "A:CONFIRM B:BACK"
    elseif self.focus == "tabs" then
      hint = "L/R:PICK A:OK"
    elseif self.focus == "apply" then
      hint = "A:APPLY B:BACK"
    elseif self.page == TAB_IV or self.page == TAB_EV then
      hint = "U/D:STAT L/R:VAL A:SET"
    elseif self.page == TAB_NAT then
      hint = "L/R:NATURE A:OK"
    else
      hint = "L/R:GENDER A:OK"
    end
    cell(self.status ~= "" and self.status or hint, MOVE_PAD, STATUS_Y)
    cell("START:MOVES", MOVE_PAD, HINT_Y)
    cell("B:BACK", MOVE_W - MOVE_PAD - 6 * 8, HINT_Y)
  end

  -- The staged stat total and the APPLY button beside it, bottom of the info
  -- panel, above the status line; the button is framed, and framed twice while
  -- it holds the cursor.
  function Screen:drawCostBar()
    local costText = string.format("COST:%d", self:pendingCost())
    Font.draw(costText, SX(MOVE_PAD), SX(COST_Y))
    local bw = #"APPLY" * 8 + 2 * TAB_PAD
    local bx = MOVE_W - MOVE_PAD - bw
    frame(bx, APPLY_Y, bw, APPLY_H, self.focus == "apply" and 2 or 1)
    Font.draw("APPLY", SX(bx + TAB_PAD), SX(APPLY_Y + 2))
  end

  -- The ability-swap confirmation, drawn like the MOVES page's own price
  -- prompt: a centred box naming the destination ability and the price.
  function Screen:drawAbilityConfirm()
    local info = self:abilitySwapInfo(self.abilityConfirm)
    if not info then return end
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 60, 62, 200, 52)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 62, 64, 196, 48)
    love.graphics.setColor(0, 0, 0, 1)
    cell("SET " .. string.sub(tostring(info.to), 1, 14) .. "?", 74, 72)
    cell(string.format("FOR %d  A:YES B:NO", info.cost), 74, 90)
  end

  function Screen:drawStats()
    local mon = self.mon
    local name = mon.nickname or (self.def and self.def.name) or mon.species
      or "?"
    cell("TRAIN " .. string.sub(tostring(name), 1, 18), MOVE_PAD, HEADER_Y)
    local moneyLabel = string.format("MONEY:%d", moneyOf(liveSave()))
    cell(moneyLabel, MOVE_W - MOVE_PAD - #moneyLabel * 8, HEADER_Y)
    love.graphics.rectangle("fill", MOVE_PAD, RULE1_Y, MOVE_W - 2 * MOVE_PAD, 1)

    self:drawTabs()
    love.graphics.rectangle("fill", MOVE_PAD, RULE2_Y, MOVE_W - 2 * MOVE_PAD, 1)

    self:drawSetRow()
    self:drawTable(self:preview(), self.page == TAB_IV or self.page == TAB_EV)
    self:drawPanel()
    self:drawCostBar()

    love.graphics.rectangle("fill", MOVE_PAD, RULE3_Y, MOVE_W - 2 * MOVE_PAD, 1)
    self:drawHint()
    if self.abilityConfirm then self:drawAbilityConfirm() end
  end

  function Screen:drawMoves()
    -- This page draws in its OWN enlarged surface, so the coordinates below
    -- are already screen pixels (S is 1 while this mode is up).  Header: the
    -- title top-left and the constant price top-right, then the category
    -- (LEFT/RIGHT cycles it), the wallet and the cycling hint on one line,
    -- then a hairline rule.
    cell("TRAIN MOVES", MOVE_PAD, 12)
    local costLabel = string.format("COST:%d", MOVE_COST)
    cell(costLabel, MOVE_W - MOVE_PAD - #costLabel * 8, 12)
    love.graphics.rectangle("fill", MOVE_PAD, MOVE_DIV_Y1,
      MOVE_W - 2 * MOVE_PAD, 1)
    cell("CAT:" .. MOVE_FIELD_LABELS[self.category], MOVE_PAD, 30)
    local moneyLabel = string.format("MONEY:%d", moneyOf(liveSave()))
    cell(moneyLabel, math.floor((MOVE_W - #moneyLabel * 8) / 2 + 0.5), 30)
    local catHint = "L/R:CAT"
    cell(catHint, MOVE_W - MOVE_PAD - #catHint * 8, 30)
    love.graphics.rectangle("fill", MOVE_PAD, MOVE_DIV_Y2,
      MOVE_W - 2 * MOVE_PAD, 1)

    local list = self.moveList
    if #list == 0 then
      cell(self.moveHint or "NONE TO LEARN", MOVE_PAD, MOVE_ROW_TOP)
    else
      local top = 1
      if #list > VISIBLE_MOVES then
        top = clamp(self.moveIndex - math.floor(VISIBLE_MOVES / 2), 1,
          #list - VISIBLE_MOVES + 1)
      end
      -- Two columns, filled down the left one first.  The cursor's row is
      -- the only one marked; names get 16 glyph columns where the classic
      -- 160-wide window could fit 14 in its single column.
      for i = 0, VISIBLE_MOVES - 1 do
        local index = top + i
        local entry = list[index]
        if not entry then break end
        local x = MOVE_COLS[math.floor(i / MOVE_ROWS_PER_COL) + 1]
        local y = MOVE_ROW_TOP + (i % MOVE_ROWS_PER_COL) * MOVE_ROW_STEP
        if index == self.moveIndex then cursor(x, y) end
        cell(string.sub(entry.name, 1, MOVE_NAME_MAX), x + MOVE_NAME_X, y)
      end
    end
    love.graphics.rectangle("fill", MOVE_PAD, MOVE_DIV_Y3,
      MOVE_W - 2 * MOVE_PAD, 1)
    cell(self.status ~= "" and self.status or "PICK A MOVE", MOVE_PAD,
      MOVE_STATUS_Y)
    cell("A:TEACH", MOVE_PAD, MOVE_HINT_Y)
    cell("B:BACK", MOVE_W - MOVE_PAD - 6 * 8, MOVE_HINT_Y)

    -- The forget-a-slot prompt: a centred box with the four current moves.
    if self.pickingSlot then
      local moves = self.mon.moves or {}
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", 60, 44, 200, 106)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 62, 46, 196, 102)
      love.graphics.setColor(0, 0, 0, 1)
      cell("FORGET WHICH?", 74, 52)
      for i = 1, math.max(1, #moves) do
        local y = 68 + (i - 1) * 14
        if i == self.slotIndex then cursor(74, y) end
        local move = moves[i]
        local data = self.game and self.game.data
        local def = move and data and data.moves and data.moves[move.id]
        local label = def and def.name or (move and move.id) or "----"
        if move and HM_MOVES[move.id] then label = label .. " (HM)" end
        cell(string.sub(label, 1, 16), 84, y)
      end
      cell("A:OK B:BACK", 74, 132)
    end

    -- The price confirmation.
    if self.pending then
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", 60, 68, 200, 50)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 62, 70, 196, 46)
      love.graphics.setColor(0, 0, 0, 1)
      cell("LEARN " .. string.sub(self.pending.entry.name, 1, 14) .. "?",
        74, 78)
      cell(string.format("FOR %d  A:YES B:NO", MOVE_COST), 74, 96)
    end
  end

  function Screen:draw()
    if self.broken then return end
    safeCall(self, "draw", function()
      -- Pick this page's surface and the scale its coordinates are in.  The
      -- MOVES page is the enlarged 320x180 window and draws in raw pixels
      -- (S = 1); the STATS page keeps its classic window and design scale.
      local W, H = self:uiSize()
      -- Both pages are the same 320x180 raw-pixel surface now (round 190).
      S = 1
      -- Plain drawing only.  Gen 1's Game:draw has already asked this state
      -- for :uiSize() and called Renderer:setUISize itself; Gen 2 has called
      -- drawWidescreen, which re-enters here under its own window transform.
      -- Touching the Renderer from inside draw (setUISize/setCanvas) is the
      -- silent-crash hazard stats/dev_stats_screen.lua's own header documents
      -- -- never do it.
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, W, H)
      -- The MOVES page is a full-bleed native window, so it rings its whole
      -- surface; the STATS page is the engine's own table layout and keeps
      -- its framed rows.
      drawBorder(W, H)
      love.graphics.setColor(0, 0, 0, 1)
      if self.mode == "stats" then self:drawStats() else self:drawMoves() end
      love.graphics.setColor(1, 1, 1, 1)
    end)
  end

  -- --------------------------------------------------------------- the hook
  mod.hooks:wrap("ui.party.submenu", function(nextFn, game, items, mon, ctx)
    local result = nextFn(game, items, mon, ctx)
    if type(result) ~= "table" then result = items end
    if type(result) ~= "table" then return result end
    -- Field list only (never the in-battle SWITCH/STATS box), and never an egg
    -- -- an egg has nothing to train.
    local isBattle = ctx and ctx.battle
    local isEgg = type(mon) == "table" and mon.isEgg
    local hasRoom = (isGen1Boot and true) or (#result < NUM_MONMENU_ITEMS)
    local wanted = mod.options:get("train_screen") == "true"
    if wanted and not isBattle and not isEgg and hasRoom then
      result[#result + 1] = {
        id = "TRAIN", label = "TRAIN",
        onSelect = function(selectedMon, selectedGame)
          local ok, screen = pcall(Screen.new, selectedGame, selectedMon)
          if ok and screen then
            selectedGame.stack:push(screen)
          else
            mod.log:warn("g9-battle-engine: TRAIN screen failed to open (%s)",
              tostring(screen))
          end
        end,
      }
    end
    return result
  end, 0)

  mod.log:info("g9-battle-engine: TRAIN party screen installed (Gen %d)", gen)
end
