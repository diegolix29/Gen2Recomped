-- tools/walker_events_check: every entry on the Watt Shop's Events shelf for
-- one game, bought into a SCRATCH save and delivered the way the game does on
-- load (WalkerEvents.apply), then checked against the game's own consumers:
--   * key events: the bag, the flags / vars, and the engine's port of the
--     ROM check that reads them (the SS Tidal menu, special 504, Crystal's
--     CheckGSBall, the Gen 4 deliveryman + checkdistributionevent ...)
--   * event Pokemon: the record's OT / id / moves / item / ball / fateful
--     mark / ribbons, the ROM's fateful checks (FollowerPokeIsEventTrigger,
--     GetPartySlotWithFatefulEncounter, BW 0x220), and a cartridge record
--     built from it (checksum + encryption) read back
--   * the whole save exported to a cartridge image and imported again (the
--     importer rejects a bad checksum)
--
--   GAME=emerald ROOT=G:/Gen2Recomped "C:/Program Files/LOVE/lovec.exe" tools/walker_events_check
-- Saves are written ONLY under $SCRATCH (default ROOT/scratch_claude/walker_events).
io.stdout:setvbuf("line")
package.path = "./?.lua;./?/init.lua;" .. package.path
local ffi = require("ffi")
pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
local C = (pcall(function() return ffi.C.PHYSFS_mount end) and ffi.C) or ffi.load("love")

local GAME = os.getenv("GAME") or "emerald"
local ROOT = os.getenv("ROOT") or "G:/Gen2Recomped"
local SCRATCH = os.getenv("SCRATCH") or (ROOT .. "/scratch_claude/walker_events")

local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then pass = pass + 1 else fail = fail + 1 end
  print(("%s  %s%s"):format(cond and "PASS" or "FAIL", name, (not cond and extra ~= nil) and ("  -- " .. tostring(extra)) or ""))
end

local function norm(s) return (tostring(s or ""):upper():gsub("\195\169", "E"):gsub("[^%w]", "")) end

function love.load()
  local ok, err = xpcall(function()
    local GV = require("src.core.GameVersion")
    GV.set(GAME)
    assert(C.PHYSFS_mount(ROOT .. "/" .. GAME, "", 0) ~= 0, "no imported " .. GAME .. " under " .. ROOT)
    local Data = require("src.core.Data")
    Data:load()
    local gen = GV.generation(GAME)
    local Ser = require("src.core.SaveSerializer")
    local SaveData = require("src.core.SaveData")
    local W = require("src.pokewalker.Walker")
    local E = require("src.pokewalker.WalkerEconomy")
    local Ev = require("src.pokewalker.WalkerEvents")
    local Pokemon = require("src.pokemon.Pokemon")

    -- NOTHING outside the scratch folder: the slot file, the walker state and
    -- the backups are all redirected
    os.execute(('mkdir "%s" 2>nul'):format(SCRATCH:gsub("/", "\\")))
    local slotFile = SCRATCH .. "/" .. GAME .. "_events_slot.lua"
    SaveData.slotDiskPath = function() return slotFile end
    SaveData.writeSlot = function(_, _, t)
      local f = assert(io.open(slotFile, "wb")); f:write(Ser.encode(t)); f:close()
      return true
    end
    W.save = function() end
    love.filesystem.write = function() return true end
    love.filesystem.createDirectory = function() return true end
    local function readSlot()
      local f = assert(io.open(slotFile, "rb")); local b = f:read("*a"); f:close()
      return Ser.decode(b)
    end

    -- the save the events go into: a copy of the real Crystal save when
    -- there is one (read, never written), else a fresh table
    local realCrystal = os.getenv("APPDATA") and (os.getenv("APPDATA") .. "/Gen2Recomp/saves/" .. GAME .. "/slot1.lua")
    local realBytes
    if realCrystal and (GAME == "crystal" or GAME == "gold") then
      local f = io.open(realCrystal, "rb")
      if f then realBytes = f:read("*a"); f:close() end
    end
    local function baseSave()
      local s
      if realBytes then
        s = Ser.decode(realBytes)
        s.walkerEvents = nil
        -- room in the party, as a player would make for a gift
        while #(s.party or {}) > 3 do table.remove(s.party) end
      else
        s = { version = GAME, player = { name = "WALKER", id = 12345, secretId = 54321, gender = "boy" },
              flags = {}, inventory = {}, party = {}, money = 0, nationalDex = true, hallOfFame = 0 }
      end
      s.flags = s.flags or {}
      s.inventory = s.inventory or {}
      return s
    end
    print(("== %s (gen %d)%s: %d events"):format(GAME, gen, realBytes and ", real save copy" or "", #Ev.forGame(GAME)))

    local G2 = gen == 2 and require("src.script.Gen2Commands")
    local G3 = gen == 3 and require("src.script.Gen3Commands")
    local Cmd = gen >= 4 and require("src.script.Commands")
    local G4 = gen >= 4 and require("src.script.Gen4Commands")
    local function moveNames(mon)
      local out = {}
      for _, m in ipairs(mon.moves or {}) do
        local d = Data.moves[m.id]
        out[#out + 1] = norm(d and d.name)
      end
      return table.concat(out, ",")
    end
    local function want(names)
      local out = {}
      local alias = { FEINTATTACK = "FAINTATTACK" }
      for _, n in ipairs(names or {}) do out[#out + 1] = norm(n) end
      for i, n in ipairs(out) do
        local ok = false
        for _, d in pairs(Data.moves) do if type(d) == "table" and norm(d.name) == n then ok = true break end end
        if not ok and alias[n] then out[i] = alias[n] end
      end
      return table.concat(out, ",")
    end
    local function findMon(save, id)
      for i, m in ipairs(save.party or {}) do if m.walkerEvent == id then return m, "party", i end end
      for _, b in ipairs(save.boxes or {}) do
        for _, m in pairs(b.mons or b) do if type(m) == "table" and m.walkerEvent == id then return m, "pc" end end
      end
    end

    local exported = {}
    for _, ev in ipairs(Ev.forGame(GAME)) do
      local tag = ev.id
      local base = baseSave()
      SaveData.writeSlot(GAME, "slot1", base)
      local target = { version = GAME, slot = "slot1" }
      local st = W.newState(); st.watts = 100000
      -- the prerequisite (FireRed's National Pokedex) is enforced
      if ev.needs == "natdex" or (GAME == "firered" and ev.kind == "mon" and ev.mon.species > 151) then
        local noDex = baseSave(); noDex.nationalDex = false
        SaveData.writeSlot(GAME, "slot1", noDex)
        local okN, whyN = E.buyEvent(st, ev, target)
        check(tag .. ": refused before the National Pokedex", not okN and tostring(whyN):find("National"), whyN)
        SaveData.writeSlot(GAME, "slot1", base)
      end
      -- what the shop card shows: a fresh save offers it (nil), not "no save"
      -- (the `save and blocked() or "no save"` slip showed every card so)
      local shown = Ev.statusFor(GAME, "slot1")[ev.id]
      check(tag .. ": the shop shows it buyable", shown == nil, shown)
      local spent0 = E.econ(st).counters.spent or 0
      local okB, whyB = E.buyEvent(st, ev, target)
      check(tag .. ": the shop then shows it claimed", Ev.statusFor(GAME, "slot1")[ev.id] == "claimed",
            Ev.statusFor(GAME, "slot1")[ev.id])
      check(tag .. ": bought (" .. ev.price .. " W)", okB and (E.econ(st).counters.spent or 0) - spent0 == ev.price, whyB)
      local okD, whyD = E.buyEvent(st, ev, target)
      check(tag .. ": not sold twice", not okD and whyD == "claimed", whyD)
      local save = readSlot()
      check(tag .. ": queued in the save", save.walkerEvents and #save.walkerEvents.pending == 1)
      local n = Ev.apply(save, Data)
      check(tag .. ": delivered on load", n == 1 and #save.walkerEvents.pending == 0, n)
      local ctx = { save = save, game = { data = Data, save = save, stringBuffers = {} } }

      -- ------------------------------------------------ key events
      if ev.handler == "gsball" then
        check(tag .. ": CheckGSBall answers GS_BALL_AVAILABLE", G2.gsBallAvailable(save) == true)
        check(tag .. ": a save without it is not offered the ball", G2.gsBallAvailable(baseSave()) ~= true
          or (baseSave().flags or {}).EVENT_G2_0068 == true)
      elseif ev.handler == "tidal" then
        local item = Data.items[ev.item]
        check(tag .. ": " .. ev.item .. " in the KEY ITEMS pocket", (save.inventory[ev.item] or 0) >= 1
          and item and item.pocket == "KEY_ITEM", item and item.pocket)
        save.gen3Vars = save.gen3Vars or {}
        save.gen3Vars[G3.TIDAL_PORT_VAR] = 0
        local list = G3.tidalDestinations(ctx, false) or {}
        local found = false
        for _, row in ipairs(list) do if row.item == ev.item then found = true end end
        check(tag .. ": the SS Tidal sails there (tidalDestinations)", found)
        local before = baseSave(); before.gen3Vars = { [G3.TIDAL_PORT_VAR] = 0 }
        local had = false
        for _, row in ipairs(G3.tidalDestinations({ save = before, game = ctx.game }, false) or {}) do
          if row.item == ev.item then had = true end
        end
        check(tag .. ": ...and did not before", not had)
        if ev.received then check(tag .. (": FLAG_RECEIVED %03X set"):format(ev.received), save.flags[Ev.flagKey(ev.received)] == true) end
        if ev.item == "EON_TICKET" then
          check(tag .. ": special 504 ShouldDistributeEonTicket = 1", G3.SPECIALS[504](ctx) == 1)
        end
        local MG3 = require("src.ui.Gen3MysteryGift")
        save.hallOfFame = 1
        check(tag .. ": the Hall-of-Fame pick is still owed", MG3.owed({ save = save, data = Data }) == 1)
      elseif ev.handler == "frlg" then
        local item = Data.items[ev.item]
        check(tag .. ": " .. ev.item .. " in the KEY ITEMS pocket", (save.inventory[ev.item] or 0) >= 1
          and item and item.pocket == "KEY_ITEM", item and item.pocket)
        for _, fl in ipairs(ev.flags) do
          check(tag .. (": flag %03X set"):format(fl), save.flags[Ev.flagKey(fl)] == true)
        end
        -- VermilionCity_EventScript_CheckHas<...>Ticket: goto_if_unset FLAG_ENABLE_SHIP_*, checkitem
        check(tag .. ": Vermilion's ticket check passes", save.flags[Ev.flagKey(ev.flags[1])] == true
          and (save.inventory[ev.item] or 0) > 0)
      elseif ev.handler == "gen4" then
        local MG = require("src.pokemon.Gen4MysteryGift")
        local gave, guard = {}, 0
        while MG.current(save) and guard < 8 do
          guard = guard + 1
          G4.setVar(save, 0x8000, 0)
          Cmd.g4_mystery_gift(ctx, 1, 0x8000)
          local g = MG.current(save)
          gave[#gave + 1] = g.key
          Cmd.g4_mystery_gift(ctx, 3, 0x8001)
          Cmd.g4_mystery_gift(ctx, 5, 0x8002, 0x8003)
          check(tag .. ": deliveryman has " .. g.key .. " (bank " .. G4.getVar(save, 0x8002) .. ", line " .. G4.getVar(save, 0x8003) .. ")",
            G4.getVar(save, 0x8000) == 1 and G4.getVar(save, 0x8001) == 1)
          Cmd.g4_mystery_gift(ctx, 4)
        end
        check(tag .. ": handed over " .. table.concat(gave, ", "), #gave >= 1)
        if ev.gift.item then
          local d = Data.items[ev.gift.item]
          check(tag .. ": item " .. ev.gift.item .. " in the bag (" .. tostring(d and d.pocket) .. ")",
            (tonumber(save.inventory[ev.gift.item]) or 0) >= 1 and d and d.pocket == "KEY_ITEMS")
        end
        if ev.gift.event then
          Cmd.g4_check_distribution_event(ctx, ev.gift.event, 0x8004)
          check(tag .. ": checkdistributionevent " .. ev.gift.event .. " = 1", G4.getVar(save, 0x8004) == 1)
        end
        if ev.gift.type == 7 then
          local egg
          for _, m in ipairs(save.party) do if m.isEgg and (m.species == 490 or Data.pokemon[m.species] and Data.pokemon[m.species].name == "Manaphy") then egg = m end end
          check(tag .. ": a Manaphy Egg in the party", egg ~= nil)
        end
        check(tag .. ": not offered again at the Hall of Fame", (function()
          for _, g in ipairs(MG.available(save)) do if g.key == ev.base then return false end end
          return true end)())
      elseif ev.handler == "gen5" then
        check(tag .. ": Liberty Pass (574) in the bag", (tonumber(save.inventory[574]) or tonumber(save.inventory.ITEM_574) or 0) >= 1)
        local MG5 = require("src.pokemon.Gen5MysteryGift")
        MG5.recordClear(save)
        check(tag .. ": the per-clear pick is still owed", MG5.owed(save) == 1)
      end

      -- ------------------------------------------------ event Pokemon
      if ev.kind == "mon" then
        local m = ev.mon
        if gen == 4 then
          local MG = require("src.pokemon.Gen4MysteryGift")
          local guard = 0
          while MG.current(save) and guard < 8 do
            guard = guard + 1
            G4.setVar(save, 0x8001, 0)
            Cmd.g4_mystery_gift(ctx, 3, 0x8001)
            if G4.getVar(save, 0x8001) ~= 1 then break end
            Cmd.g4_mystery_gift(ctx, 4)
          end
        end
        local mon, where, slot = findMon(save, ev.id)
        check(tag .. ": in the " .. tostring(where), mon ~= nil)
        if mon then
          local def = Data.pokemon[mon.species]
          check(tag .. ": species #" .. m.species, def and (tonumber(def.dex) == m.species or mon.species == m.species), def and def.dex)
          check(tag .. ": level " .. tostring(m.level), mon.level == m.level, mon.level)
          if m.ot then
            check(tag .. ": OT " .. m.ot .. " / " .. m.tid, mon.ot == m.ot
              and (tonumber(mon.otId) or 0) % 65536 == m.tid, tostring(mon.ot) .. "/" .. tostring(mon.otId))
          end
          if #m.moves > 0 and not m.egg then
            check(tag .. ": moves " .. want(m.moves), moveNames(mon) == want(m.moves), moveNames(mon))
          end
          if m.item then
            local d = Data.items[mon.item]
            check(tag .. ": holds " .. m.item, d and norm(d.name) == norm(m.item), mon.item)
          end
          if m.ball and gen >= 3 then
            local d = Data.items[mon.ball]
            check(tag .. ": in a " .. m.ball, d and norm(d.name) == norm(m.ball), mon.ball)
          end
          if m.fateful then check(tag .. ": fateful encounter", mon.fatefulEncounter == true) end
          if m.egg then check(tag .. ": an egg", mon.isEgg == true and (mon.eggSteps or 0) > 0) end
          if m.shiny then check(tag .. ": shiny", Pokemon.isShiny(mon)) end
          if m.pid and gen >= 3 then check(tag .. (": personality %08X"):format(m.pid), mon.personality == m.pid) end
          -- what the ROM's own checks see
          if gen == 4 and slot then
            if m.species == 251 and (GAME == "heartgold" or GAME == "soulsilver") then
              Cmd.g4_follower_event_trigger(ctx, 3, slot - 1, 0x8005)
              check(tag .. ": FollowerPokeIsEventTrigger CELEBI = 1 (Ilex Forest)", G4.getVar(save, 0x8005) == 1)
            elseif m.species == 493 and (GAME == "heartgold" or GAME == "soulsilver") then
              Cmd.g4_follower_event_trigger(ctx, 1, slot - 1, 0x8005)
              check(tag .. ": FollowerPokeIsEventTrigger ARCEUS = 1 (Sinjoh Ruins)", G4.getVar(save, 0x8005) == 1)
            elseif m.species == 492 or m.species == 486 then
              Cmd.g4_fateful_slot(ctx, 0x8005, m.species)
              check(tag .. ": GetPartySlotWithFatefulEncounter finds it", G4.getVar(save, 0x8005) == slot - 1)
            end
          end
          if gen == 5 and slot and ev.about then
            Cmd.g4_bw_event_mon(ctx, m.species, 0x8006, 0x8007)
            check(tag .. ": BW 0x220 sees a fateful #" .. m.species .. " (" .. ev.about .. ")", G4.getVar(save, 0x8007) == 1)
          end
          -- a cartridge record built from it, read back
          if gen == 3 then
            local SC = require("src.save_convert.SaveConvert")
            local cw = assert(SC.loadData(GAME))
            local G3S = require("src.save_convert.Gen3Save")
            local rec = G3S.buildBoxMon(mon, G3S.crosswalks(cw), { id = save.player.id, secretId = save.player.secretId, name = save.player.name })
            local dm = G3S.decodeBoxMon(rec, 0)
            check(tag .. ": PK3 checksum", dm.checksumOk)
            check(tag .. ": PK3 personality / trainer id", dm.personality == mon.personality
              and dm.otId == (m.tid or save.player.id) + (m.sid or (m.ot and 0 or save.player.secretId)) * 65536,
              ("%08X %08X"):format(dm.personality, dm.otId))
            -- the ribbon word (misc +8): fateful mark and ribbons
            local function u32(s, o) local a, b, c, d = s:byte(o + 1, o + 4) return a + b * 256 + c * 65536 + d * 16777216 end
            local key = bit.bxor(dm.personality, dm.otId)
            local order = G3S.substructOrders[(dm.personality % 24) + 1]
            local misc = order[4] * 12
            local rib = bit.bxor(u32(rec, 32 + misc + 8), key) % 4294967296
            if rib < 0 then rib = rib + 4294967296 end
            local ivw = bit.bxor(u32(rec, 32 + misc + 4), key) % 4294967296
            if ivw < 0 then ivw = ivw + 4294967296 end
            if os.getenv("DEBUG") then print(("    dbg ivWord %08X decoded %08X order %s len %d"):format(ivw, dm.ivWord, table.concat(order, ","), #rec)) end
            check(tag .. (": PK3 ribbon word %08X"):format(m.ribbons3 or 0), rib == (m.ribbons3 or 0), ("%08X"):format(rib))
          elseif gen >= 4 then
            local Nds = require("src.save_convert.NdsSave")
            local G4S = require("src.save_convert.Gen4Save")
            local nctx = G4S.context(Data, (GAME == "heartgold" or GAME == "soulsilver") and "hgss" or "pt", GAME, save.player)
            if gen == 5 then
              nctx.gen, nctx.family, nctx.text, nctx.gameId = 5, "bw", Nds.textCodec(5), GAME == "white" and 20 or 21
            end
            local canon = Nds.encodeMon(mon, nctx, 236)
            local dec, okSum = Nds.decryptPkm(Nds.encryptPkm(canon))
            check(tag .. ": PK" .. gen .. " checksum", okSum)
            local back = Nds.decodeMon(dec, nctx, true)
            check(tag .. ": PK" .. gen .. " species / OT / fateful", back.species == m.species
              and back.fatefulEncounter == (m.fateful or nil) and (not m.ot or back.ot == m.ot)
              and (not m.tid or back.otId == m.tid + (m.sid or 0) * 65536), tostring(back.ot) .. "/" .. tostring(back.otId))
            local function u32(s, o) local a, b, c, d = s:byte(o + 1, o + 4) return a + b * 256 + c * 65536 + d * 16777216 end
            local words = m.ribbons4 or (m.ribbons5 and Ev.pgfRibbonWords(m.ribbons5)) or { 0, 0, 0 }
            check(tag .. (": PK%d ribbons %08X %08X"):format(gen, words[1], words[2]), u32(dec, 0x24) == words[1] and u32(dec, 0x3C) == words[2],
              ("%08X %08X"):format(u32(dec, 0x24), u32(dec, 0x3C)))
            if m.shiny then check(tag .. ": PK" .. gen .. " shiny by its PID", back.shiny ~= false and Pokemon.isShiny(back)) end
          end
        end
      end
      exported[#exported + 1] = save
    end

    -- ------------------------------------------- the whole save, exported
    if gen >= 2 and #exported > 0 and os.getenv("NOEXPORT") == nil then
      local SC = require("src.save_convert.SaveConvert")
      -- one save holding the last few deliveries
      local save = exported[#exported]
      local bytes, why = SC.exportSav(save, GAME)
      check("export: a " .. GAME .. " cartridge image", bytes ~= nil, why)
      if bytes then
        local f = io.open(SCRATCH .. "/" .. GAME .. "_events_export.sav", "wb"); f:write(bytes); f:close()
        local back, why2 = SC.importSav(bytes, GAME, GAME)
        check("export: imports again (checksums valid)", back ~= nil, why2)
        if back then
          local nParty = #(back.party or {})
          check("export: party of " .. #(save.party or {}) .. " read back", nParty == math.min(6, #(save.party or {})), nParty)
          for i, m in ipairs(save.party or {}) do
            if m.walkerEvent and back.party[i] then
              local b = back.party[i]
              check("export: " .. m.walkerEvent .. " reads back (" .. tostring(b.ot) .. ")", b.otId ~= nil and
                ((tonumber(b.otId) or 0) % 65536 == (tonumber(m.otId) or 0) % 65536), tostring(b.otId))
            end
          end
        end
      end
    end
  end, debug.traceback)
  if not ok then print("FAILED: " .. tostring(err)); fail = fail + 1 end
  print(("RESULT %s: %d passed, %d failed"):format(GAME, pass, fail))
  love.event.quit(fail == 0 and 0 or 1)
end
