-- HEARTGOLD AND SOULSILVER'S `constants` (and `type_chart`).
--
-- Platinum's constants stage (RomExtractorGen4:extractConstants) mixes the
-- game-independent with the Sinnoh-only: the type chart, the curves and the
-- TM list sit beside Poketch art, Honey trees, the Underground and Platinum's
-- mart -- whose paths HGSS does not have. This builds the table for HGSS from
-- the same finders, in its own module so Platinum's stage is left as it is.
--
--   type chart     Gen4TypeChart's signature scan over the overlays, which
--                  NdsRom now unpacks (127 of HGSS's 129 are BLZ-compressed)
--   types, natures the HGSS banks Gen4Versions names (735, 34)
--   curves         /a/0/0/3 (poketool_personal_growtbl), six of 101 u32
--   TMs and HMs    the same tail search as Platinum's with HGSS's HMs:
--                  Cut, Fly, Surf, Strength, WHIRLPOOL (250, where Platinum
--                  has Defog), Rock Smash, Waterfall, Rock Climb
--   badges         pokeheartgold include/constants/badge.h, Johto then Kanto
--   new game       the init band's script (scr_seq 149, entry 0): every
--                  SetFlag / ClearFlag / SetVar it runs, as Platinum's is read
--   message window 2, 19, 27 x 4 -- the rectangle HGSS's own windows use
--                  (options_app.c, choose_starter_app.c, naming_screen.c)
--
-- Not built yet, and absent rather than borrowed from Platinum: marts,
-- berries, trades, shadows, honey trees.

local C = {}

C.HM_TAIL = { 15, 19, 57, 70, 250, 249, 127, 431 }
C.NUM_TMS, C.NUM_HMS = 92, 8
C.BADGES = { "ZEPHYR", "HIVE", "PLAIN", "FOG", "STORM", "MINERAL", "GLACIER", "RISING",
             "BOULDER", "CASCADE", "THUNDER", "RAINBOW", "SOUL", "MARSH", "VOLCANO", "EARTH" }
C.GROWTH = { "MEDIUM_FAST", "ERRATIC", "FLUCTUATING", "MEDIUM_SLOW", "FAST", "SLOW" }

local function tmhm(arm9)
  local needle = {}
  for _, v in ipairs(C.HM_TAIL) do needle[#needle + 1] = string.char(v % 256, math.floor(v / 256)) end
  needle = table.concat(needle)
  local p = arm9:find(needle, 1, true)
  while p do
    local start = p - C.NUM_TMS * 2
    if start >= 1 then
      local list, seen, good = {}, {}, true
      for i = 0, C.NUM_TMS + C.NUM_HMS - 1 do
        local a, b = arm9:byte(start + i * 2, start + i * 2 + 1)
        local v = (a or 0) + (b or 0) * 256
        if v == 0 or seen[v] then good = false end
        seen[v] = true
        list[i + 1] = v
      end
      if good then return list, start - 1 end
    end
    p = arm9:find(needle, p + 1, true)
  end
  return nil
end

-- build(x) -> constants, typeChart, report; `x` is the RomExtractorGen4
function C.build(x)
  local TypeChart = require("src.import.Gen4TypeChart")
  local report = {}
  local chart, parsed
  for overlay = 0, 140 do
    local ok, bytes = pcall(function() return x.rom:overlay(overlay) end)
    if ok and bytes and #bytes > 0 then
      local at = TypeChart.find(bytes)
      parsed = at and TypeChart.parse(bytes, at)
      if parsed then
        parsed.overlay = overlay
        chart = TypeChart.chart(parsed)
        break
      end
    end
  end
  report.chartOverlay = parsed and parsed.overlay

  local BANK = require("src.import.RomExtractorGen4").BANK
  local types, natures = {}, {}
  for i = 0, TypeChart.TYPE_COUNT - 1 do types[i] = x:string(BANK.typeName, i) or TypeChart.TYPES[i] end
  for i = 0, 24 do natures[i + 1] = x:string(BANK.nature, i) end

  local curves
  local growth = x:archive("growthTables")
  if growth then
    curves = {}
    for i, name in ipairs(C.GROWTH) do
      local m = growth:get(i - 1)
      if m and #m >= 404 then
        local curve = {}
        for level = 0, 100 do
          local a, b, c, d = m:byte(level * 4 + 1, level * 4 + 4)
          curve[level + 1] = a + b * 256 + c * 65536 + d * 16777216
        end
        curves[name] = curve
      end
    end
  end

  local arm9 = x.rom:arm9()
  local tms, tmAt = tmhm(arm9)
  report.tmhmAt = tmAt

  -- the new game's world state, out of the init band's script
  local newGame
  do
    local Bands = require("src.import.Gen4ScriptBands")
    local Script = require("src.import.Gen4Script")
    local VM = require("src.script.Gen4ScriptVM")
    local Ops = require("src.import.Gen4HgssScriptOps")
    local Aliases = require("src.import.Gen4HgssScriptAliases")
    local member
    for _, band in ipairs(Bands.HGSS.BANDS) do if band[2] == "init" then member = band[3] end end
    local arc = member and x:archive("scripts")
    local bytes = arc and arc:get(member)
    local entries = bytes and Script.entries(bytes)
    if entries and entries[1] then
      local flags, cleared, vars, seen, queue = {}, {}, {}, { [entries[1]] = true }, { entries[1] }
      local i = 1
      while i <= #queue do
        local at = queue[i]; i = i + 1
        for _, ins in ipairs((Script.decode(bytes, at, Ops))) do
          local t = ins.target
          if t and t >= 1 and t <= #bytes and not seen[t] then seen[t] = true; queue[#queue + 1] = t end
          Aliases.apply(ins)
          if ins.name == "setflag" then flags[#flags + 1] = VM.flagName(ins.args[1])
          elseif ins.name == "clearflag" then cleared[#cleared + 1] = VM.flagName(ins.args[1])
          elseif ins.name == "setvarfromvalue" then vars[#vars + 1] = { id = ins.args[1], value = ins.args[2] } end
        end
      end
      newGame = { flags = flags, cleared = cleared, vars = vars, member = member,
                  source = ("ROM:scr_seq %d entry 0, %d SetFlag / %d ClearFlag / %d SetVar")
                    :format(member, #flags, #cleared, #vars) }
    end
  end

  local function order(n) local t = {} for i = 1, n do t[i] = i end return t end
  local badges = {}
  for i, id in ipairs(C.BADGES) do badges[i] = { id = "BADGE_" .. id } end

  -- IN-GAME TRADES: /a/1/1/2, one 0x54-byte record per trade (npc_trade.c
  -- NPCTrade). Its first twenty u32s are Platinum's NPCTradeMon field for
  -- field -- HGSS uses the two Platinum leaves unused for ability and sheen --
  -- so Gen4Trades reads them unchanged. Thirteen trades (constants/
  -- npc_trade.h, Rocky's Onix first); bank 200 holds the nicknames and then
  -- the OT names (NPC_TRADE_OT_NUM = id + 13).
  local trades
  do
    local Gen4Trades = require("src.import.Gen4Trades")
    local arc = x:archiveAt("/a/1/1/2")
    local names
    local bank = x:bank(200)
    if bank then
      names = {}
      for i = 0, bank.count - 1 do names[i + 1] = x:string(200, i) end
    end
    trades = arc and Gen4Trades.all(arc, names, 13) or nil
    if trades then trades.source = "ROM:/a/1/1/2 (13 records of 84 bytes) + bank 200" end
  end
  local constants = {
    gen4Trades = trades,
    gen = 4, generation = 4, family = "hgss",
    experienceTables = curves,
    tmhmMoves = tms,
    badges = badges,
    gen4NewGame = newGame,
    gen4MessageWindow = { left = 2, top = 19, width = 27, height = 4,
      source = "pokeheartgold: options_app.c / choose_starter_app.c / naming_screen.c (2, 19, 27, 4)" },
    gen4Screen = { width = 256, height = 192 },
    types = types,
    typeCount = TypeChart.TYPE_COUNT,
    natures = natures,
    natureOrder = order(25),
    speciesOrder = order(493),
    world = { blockPx = 16, stepFrames = 8, runStepFrames = 4 },
    source = ("ROM:%s (types bank %d, natures bank %d, type chart overlay %s)")
      :format(x.version, BANK.typeName, BANK.nature, tostring(report.chartOverlay)),
  }
  report.newGameFlags = newGame and #newGame.flags or 0
  return constants, chart, report
end

return C
