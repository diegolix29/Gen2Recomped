-- Modern Pokemon stats display for Gen1Recomp.
--
-- Layout strategy:
--   * The engine still renders a pixel-exact UI canvas and scales that canvas
--     to the device.  We therefore do NOT scale individual widgets ourselves.
--   * This screen requests a 256x144 logical UI surface (32x18 GB pixels).
--     That gives us 96 extra horizontal pixels without changing the physical
--     device resolution, aspect handling, or nearest-neighbor scaling.
--   * The extra width is used to separate the information into two clean
--     columns instead of squeezing modern fields into the original 160px
--     summary layout.
--
-- Opt-in (round 106, 2026-09-10): this screen used to install
-- unconditionally and repoint the party menu's STATS action at itself.
-- It is now gated behind the "modern_stats_screen" option (options.lua),
-- OFF by default, so the STATS action opens the game's native party
-- summary screen unless the user turns MODERN STATS SCREEN on. Adv.Stats
-- (stats/dev_stats_screen.lua) is this mod's modern stats display and is
-- unaffected by this gate. (Gen 2 already never installed this screen --
-- see isGen2Boot below.)
--
-- Renderer:setUISize() is the supported engine extension point for a wider UI
-- surface; no engine file is modified by this mod.
return function(mod)
  local ModernStats = mod.exports.ModernStats
  local MoveCategory = mod.exports.MoveCategory
  local Stats = require("src.pokemon.Stats")
  local Sprites = require("src.pokemon.Sprites")
  local TypeChart = require("src.battle.TypeChart")
  local Growth = require("src.pokemon.Growth")
  local Font = require("src.render.Font")
  local HudTiles = require("src.render.HudTiles")
  local Strings = require("src.core.Strings")
  local Renderer = require("src.render.Renderer")
  local GameVersion = require("src.core.GameVersion")

  -- TEMPORARY: this screen was built and verified only against Gen 1
  -- party mon shapes -- disabled on a Gen 2 boot for now (native STATS
  -- menu behavior stays untouched there) rather than shipping it
  -- unverified. Same boot-time detection main.lua's own evolution-patch
  -- pass already uses. Revisit and re-enable once checked against Gen 2.
  local isGen2Boot = GameVersion.generation(GameVersion.get()) == 2

  local SCREEN_ID = "GgdModernStats"
  local UI_W, UI_H = 256, 144
  local NONE = "----"

  local function safeText(value)
    if value == nil or tostring(value) == "" then return NONE end
    return tostring(value)
  end

  -- Clip by rendered glyph width rather than bytes. This also behaves correctly
  -- when the active font uses variable-width TTF glyphs.
  local function fitText(value, maxWidth)
    local text = safeText(value)
    if Font.width(text) <= maxWidth then return text end
    local spans = Font.split(text)
    local out = ""
    local used = 0
    for _, span in ipairs(spans) do
      local glyph = text:sub(span.from, span.to)
      local w = Font.width(glyph)
      if used + w > maxWidth then break end
      out = out .. glyph
      used = used + w
    end
    return out
  end

  local function drawRight(text, rightX, y)
    local s = safeText(text)
    Font.draw(s, rightX - Font.width(s), y)
  end

  local function getMoveData(game, mon, index)
    local mv = mon.moves and mon.moves[index]
    if not mv then return nil end
    local mdef = game.data.moves and game.data.moves[mv.id]
    local cat = mdef and MoveCategory.of(mdef)
    local maxPP = mdef and ((mdef.pp or 0) + (mv.ppUps or 0)
      * math.floor((mdef.pp or 0) / 5)) or 0
    return mdef, cat, mv, maxPP
  end

  local function printLevel(tx, ty, level)
    local x = tx * 8
    if level < 100 then
      HudTiles.statusTile(0x6E, x, ty * 8)
      x = x + 8
    end
    Font.draw(tostring(level), x, ty * 8)
  end

  local function moveCategoryText(mdef)
    local cat = mdef and MoveCategory.of(mdef)
    if cat == "Physical" then return "PHY" end
    if cat == "Special" then return "SPE" end
    if cat == "Status" then return "STA" end
    return "---"
  end

  local function drawLabelValue(label, value, xLabel, xValue, y, valueWidth)
    Font.draw(label, xLabel, y)
    Font.draw(fitText(value, valueWidth), xValue, y)
  end

  local Screen = {}
  Screen.__index = Screen
  Screen.isOpaque = true
  Screen.screenId = SCREEN_ID

  -- The renderer will integer-scale this 256x144 canvas to whatever physical
  -- resolution the device provides. It is NOT a fixed window size.
  function Screen:uiSize()
    return UI_W, UI_H
  end

  function Screen.new(game, mon)
    local def = game.data.pokemon[mon.species]
    Stats.ensure(def, mon)
    ModernStats.ensure(def, mon)
    -- Ability/nature generation is otherwise only wired to battle.started
    -- (gen2_modern_stats.lua/wild_modern_ivs.lua/trainer_modern_stats.lua),
    -- so a mon viewed here before its first battle (a starter, a gift, a
    -- trade) would still show a nil ability/nature. Both generate
    -- functions are idempotent -- only fill a genuinely missing value,
    -- never re-roll one a mon already has -- so calling them here on
    -- every open is the same safe "derive on demand" contract this file
    -- already uses for ivs/evs/stats.
    local nd = mod.find and mod.find("national_dex")
    ModernStats.generateAbility(mon, ModernStats.resolveAbilities(mon.species, nd and nd.exports))
    ModernStats.generateNature(mon)
    local self = setmetatable({ game = game, mon = mon, page = 1 }, Screen)
    local path = Sprites.path(game.data, mon.species, "front", {
      mon = mon, kind = "summary"
    })
    if path then
      local ok, img = pcall(love.graphics.newImage, path)
      self.sprite = ok and img or nil
    end
    return self
  end

  function Screen:update(dt)
    local input = self.game.input
    if input:wasPressed("a") then
      self.page = self.page == 1 and 2 or 1
      return
    end
    if input:wasPressed("b") then
      self.game.stack:pop()
    end
  end

  function Screen:drawPageOne()
    local game = self.game
    local mon = self.mon
    local def = game.data.pokemon[mon.species]
    local name = mon.nickname or (def and def.name) or tostring(mon.species)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, UI_W, UI_H)
    love.graphics.setColor(0, 0, 0, 1)

    -- HEADER: left = sprite / dex number, right = identity + HP.
    if self.sprite then
      local pw, ph = self.sprite:getDimensions()
      local py = math.max(0, 56 - ph)
      -- Keep the original mirrored summary sprite treatment, but give it the
      -- whole left 10-column area instead of fighting the text column.
      -- love.graphics.draw scales/mirrors around the image's OWN origin
      -- before translating to (x,y) -- with sx=-1 the drawn region spans
      -- [x-pw, x], not [x, x+pw], so anchoring at 80+pw put the sprite over
      -- [80,150] (on top of the name text) instead of the intended [10,80]
      -- left box. Anchor at 80 so it lands inside that box instead.
      -- setColor(1,1,1,1) undoes the black set two lines up for the
      -- background rect -- love.graphics.draw multiplies the sprite's RGB
      -- by the active draw color, so without this reset the sprite rendered
      -- as a solid black silhouette (indistinguishable from the black text
      -- drawn on top of/around it). Restored to black after for the text
      -- that follows.
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(self.sprite, 80, py, 0, -1, 1)
      love.graphics.setColor(0, 0, 0, 1)
    end

    Font.draw(fitText(name, 112), 88, 8)
    printLevel(27, 2, mon.level)

    HudTiles.drawHPBar(game.data, 17, 3, mon, 1)
    drawRight(("%3d/%3d"):format(mon.hp or 0,
      mon.stats and mon.stats.hp or 0), 248, 32)
    Font.draw(Strings("STATUS/"), 136, 48)
    drawRight(mon.status or "OK", 248, 48)

    -- Header separator.  The old line-box was useful at 160px but wastes the
    -- center of a wide screen.  A simple full-width rule keeps the page calm.
    HudTiles.statusTile(0x78, 248, 56)
    for x = 240, 8, -8 do HudTiles.statusTile(0x76, x, 56) end
    HudTiles.statusTile(0x6F, 0, 56)

    -- Left panel: six modern stats.  Each row gets a full 12px rhythm.
    Font.drawBox(0, 7, 14, 11)
    local stats = {
      { "HP", mon.stats and mon.stats.hp or 0 },
      { "ATK", mon.stats and mon.stats.attack or 0 },
      { "DEF", mon.stats and mon.stats.defense or 0 },
      { "SP.ATK", mon.stats and (mon.stats.spa or mon.stats.special or 0) or 0 },
      { "SP.DEF", mon.stats and (mon.stats.spd or mon.stats.special or 0) or 0 },
      { "SPD", mon.stats and mon.stats.speed or 0 },
    }
    for i, s in ipairs(stats) do
      local y = 64 + (i - 1) * 12
      Font.draw(s[1], 8, y)
      drawRight(("%3d"):format(s[2]), 104, y + 4)
    end

    -- Right panel: identity and modern metadata.  Values are right-aligned so
    -- long labels never collide with the values.
    Font.drawBox(13, 7, 19, 11)
    local valueX = 168
    local valueRight = 248
    Font.draw(Strings("TYPE1/"), 112, 64)
    drawRight(def.types and def.types[1] and TypeChart.displayName(def.types[1])
      or "---", valueRight, 68)

    Font.draw(Strings("TYPE2/"), 112, 76)
    drawRight(def.types and def.types[2] and TypeChart.displayName(def.types[2])
      or "---", valueRight, 80)

    HudTiles.statusTile(0x73, 112, 88)
    HudTiles.statusTile(0x74, 120, 88)
    Font.draw("/", 128, 88)
    drawRight(("%05d"):format(mon.otId or game.save.player.id or 0),
      valueRight, 92)

    Font.draw(Strings("OT/"), 112, 100)
    drawRight(fitText(mon.ot or game.save.player.name or "RED", 80),
      valueRight, 104)

    Font.draw(Strings("NATURE"), 112, 112)
    drawRight(fitText(mon.nature, 80), valueRight, 116)

    Font.draw(Strings("ABIL"), 112, 124)
    drawRight(fitText(mon.ability, 80), valueRight, 128)

    love.graphics.setColor(1, 1, 1, 1)
  end

  function Screen:drawPageTwo()
    local game = self.game
    local mon = self.mon
    local def = game.data.pokemon[mon.species]

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, UI_W, UI_H)
    love.graphics.setColor(0, 0, 0, 1)

    -- EXP header is given its own right-hand area instead of sharing the narrow
    -- original 160px column with the modern item fields.
    Font.draw(Strings("EXP POINTS"), 120, 8)
    drawRight(("%d"):format(mon.exp or 0), 248, 24)
    Font.draw(Strings("LEVEL UP"), 120, 32)
    local nextExp = mon.level < 100
      and (Growth.expForLevel(def.growthRate, mon.level + 1) - (mon.exp or 0))
      or 0
    drawRight(("%d"):format(math.max(0, nextExp)), 200, 48)
    HudTiles.statusTile(0x70, 208, 48)
    printLevel(27, 6, math.min(100, mon.level + 1))

    -- Left panel: held item and the two extra mechanics fields.
    Font.drawBox(0, 7, 14, 11)
    drawLabelValue("ITEM", mon.item, 8, 48, 72, 56)
    -- Real fix, explicit user request: a mon that has never Terastallized
    -- has no mon.teraType stored yet (its only prior writer is gated on
    -- Terastallization, currently inert -- see gigantamax/tera_state.lua's
    -- own header), so reading the raw field always drew blank even though
    -- a real initial type (RNG between a dual-type mon's own two types,
    -- or its one type for a monotype) is defined. mod.exports.getTeraType
    -- lazy-rolls AND persists that initial type into mon.teraType the
    -- first time anything calls it -- simply opening this screen is now
    -- enough to both roll and SAVE it, without needing to Terastallize
    -- first.
    local teraType = mod.exports.getTeraType and mod.exports.getTeraType(mon)
    drawLabelValue("TERA", teraType, 8, 48, 96, 56)
    -- Dynamax Level is per-save, not per-mon (dynamax_state.lua's own
    -- storage contract) -- mon.dynamaxLevel never actually exists as a
    -- field, so reading it directly always drew NONE. Same value for
    -- every mon, read through the real accessor.
    local dmaxLevel = mod.exports.getDynamaxLevel and mod.exports.getDynamaxLevel()
    drawLabelValue("DMAX", dmaxLevel and tostring(dmaxLevel) or NONE,
      8, 48, 120, 56)

    -- Right panel: four moves.  Name / category / PP have explicit columns;
    -- the move name is clipped rather than being allowed to crash into PP.
    Font.drawBox(13, 7, 19, 11)
    Font.draw("MOVE", 112, 64)
    Font.draw("CAT", 192, 64)
    Font.draw("PP", 224, 64)

    for i = 1, 4 do
      local mdef, cat, mv, maxPP = getMoveData(game, mon, i)
      local y = 76 + (i - 1) * 16
      if mv then
        local name = (mdef and mdef.name) or tostring(mv.id)
        Font.draw(fitText(name, 72), 112, y)
        Font.draw(moveCategoryText(mdef), 192, y)
        drawRight(("%2d/%2d"):format(mv.pp or 0, maxPP), 248, y)
      else
        Font.draw("-", 112, y)
        Font.draw("---", 192, y)
        drawRight("--/--", 248, y)
      end
    end

    love.graphics.setColor(1, 1, 1, 1)
  end

  function Screen:draw()
    -- Game:draw() already asks the top state for :uiSize() and calls
    -- Renderer:setUISize() itself, once, before the draw loop -- confirmed
    -- from direct engine source (Game.lua's own top.uiSize branch) -- so
    -- this SHOULDN'T be necessary. Asserted here anyway, every frame,
    -- because live testing showed content getting clipped at the old
    -- 160px boundary despite that automatic path -- something else in
    -- this frame (most likely gen1_modern_ui's own render.compose/
    -- render.hud hooks, which also touch canvas state) was winning the
    -- race after Game.lua's own call and before this state's own draw.
    -- Calling it again right here, last, guarantees the canvas is
    -- actually 256x144 by the time anything below this line draws,
    -- regardless of what ran earlier in the same frame.
    --
    -- setUISize only swaps Renderer.canvas (a new PixelCanvas) -- it does
    -- NOT rebind love.graphics' active render target, since normally
    -- Renderer:beginFrame's own love.graphics.setCanvas(self.canvas) call
    -- (which already ran once for this frame, before the draw loop) is
    -- what does that, every frame, unconditionally. Calling setUISize
    -- again HERE, after beginFrame already bound whatever canvas existed
    -- at that point, means that binding is now stale if the size check
    -- above just reallocated -- everything drawn after this line would
    -- otherwise still target the OLD (released) canvas. Re-binding
    -- explicitly closes that gap.
    Renderer:setUISize(UI_W, UI_H)
    love.graphics.setCanvas(Renderer.canvas)
    if self.page == 2 then
      self:drawPageTwo()
    else
      self:drawPageOne()
    end
  end

  mod.hooks:wrap("ui.party.submenu", function(nextFn, game, items, mon, ctx)
    local result = nextFn(game, items, mon, ctx)
    if type(result) ~= "table" then result = items end
    -- OFF by default (options.lua "modern_stats_screen", round 106): when
    -- off, the party menu's STATS action is left completely untouched and
    -- opens the game's native party summary screen instead of this one.
    -- Read lazily here -- this wrap runs long after boot, when main.lua's
    -- debug_options boot has already defined the schema (the same lazy
    -- pattern adv_stats_screen.lua uses for its own submenu entry).
    if not isGen2Boot and not (ctx and ctx.battle)
        and mod.options:get("modern_stats_screen") == "true" then
      for _, item in ipairs(result) do
        if item.action == "stats" or item.label == "STATS" then
          item.action = nil
          item.onSelect = function(selectedMon, selectedGame)
            selectedGame.stack:push(Screen.new(selectedGame, selectedMon))
          end
          break
        end
      end
    end
    return result
  end, 0)

  mod.log:info("g9-battle-engine: 256x144 modern stats screen installed (MODERN STATS SCREEN option, default OFF)")
end
