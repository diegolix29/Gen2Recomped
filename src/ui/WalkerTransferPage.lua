-- THE MONSTER WALKER'S TRANSFER PAGE (the "Transfer" tile): the two ways the
-- DS games brought Pokemon forward, run from the launcher.
--
--   PAL PARK       six from a Ruby / Sapphire / Emerald / FireRed / LeafGreen
--                  save into a Diamond / Pearl / Platinum / HeartGold /
--                  SoulSilver save's Pal Park (src/world/Gen4PalPark.lua) --
--                  the Catching Show is then played in that game
--   POKE TRANSFER  six from a Generation IV save into a Black / White save,
--                  waiting at the Poke Transfer Lab on Route 15
--                  (src/world/Gen5PokeTransfer.lua), where they are caught
--
-- The Walker's own catches can fill places in either (src/pokemon/CrossGen.lua).
-- Every save touched is backed up first; nothing can be sent back.

local W = require("src.pokewalker.Walker")

local M = {}

M.MODES = {
  palpark = { label = "Pal Park", from = { "ruby", "sapphire", "emerald", "firered", "leafgreen" },
              to = { "diamond", "pearl", "platinum", "heartgold", "soulsilver" }, maxDex = 386 },
  transfer = { label = "Poke Transfer", from = { "diamond", "pearl", "platinum", "heartgold", "soulsilver" },
               to = { "black", "white" }, maxDex = 493 },
}

function M.install(P)
  local C = P.COLORS
  local INK, DIM, GOLD, CARD, ACCENT, RED = C.INK, C.DIM, C.GOLD, C.CARD, C.ACCENT, C.RED
  local card, setc, hovered = P._card, P._setc, P._hovered

  local function gameName(v)
    local ok, GV = pcall(require, "src.core.GameVersion")
    local info = ok and GV.info(v)
    return info and (info.launcherName or info.displayName) or tostring(v)
  end

  -- every save of these games: { version, slot, label }
  local function saves(versions)
    local SaveData = require("src.core.SaveData")
    local out = {}
    for _, v in ipairs(versions) do
      local okL, slots = pcall(SaveData.listSlots, v)
      for _, s in ipairs(okL and slots or {}) do
        if s.exists then out[#out + 1] = { version = v, slot = s.id, label = s.label or s.name or s.id } end
      end
    end
    return out
  end

  local function tx(self)
    self.tx = self.tx or { mode = "palpark", picks = {} }
    return self.tx
  end

  local function reset(self, keepMode)
    local t = tx(self)
    self.tx = { mode = keepMode and t.mode or "palpark", picks = {} }
  end

  -- the source's PC (and the Walker's catches), with why each may not come
  local function list(self, t)
    if t.list and t.listKey == (t.from and (t.from.version .. "/" .. t.from.slot)) then return t.list end
    local out = {}
    if t.from then
      local Link = require("src.pokewalker.WalkerLink")
      local mons = Link.boxMons(t.from.version, t.from.slot) or {}
      local CG = require("src.pokemon.CrossGen")
      local src = CG.sourceData(t.from.version)
      local refuse = t.mode == "palpark" and require("src.world.Gen4PalPark").refusal
                     or require("src.world.Gen5PokeTransfer").refusal
      for _, e in ipairs(mons) do
        local dex = tonumber(e.species)
        local why = refuse(src, e.raw)
        if not why and dex and dex > M.MODES[t.mode].maxDex then why = "species" end
        out[#out + 1] = { kind = "pc", e = e, species = dex, name = e.name, level = e.level, why = why }
      end
    end
    for i, c in ipairs(self.st.caught or {}) do
      local dex = tonumber(c.species)
      out[#out + 1] = { kind = "walker", walker = i, entry = c, species = dex, name = c.name, level = c.level,
                        why = (dex and dex > M.MODES[t.mode].maxDex) and "species" or nil, fromWalker = true }
    end
    t.list, t.listKey = out, t.from and (t.from.version .. "/" .. t.from.slot) or "walker"
    return out
  end

  local WHY = { egg = "Egg", hm = "Knows an HM", item = "Holding an item", species = "Not in that game" }

  local function picked(t, m) for i, p in ipairs(t.picks) do if p == m then return i end end end

  local function run(self, t)
    local mode = t.mode
    local ok, why
    if mode == "palpark" then
      local PalPark = require("src.world.Gen4PalPark")
      local CG = require("src.pokemon.CrossGen")
      local picks = {}
      for i, m in ipairs(t.picks) do
        picks[i] = m.kind == "walker" and { walker = m.walker, entry = m.entry }
                   or { box = m.e.source.box, index = m.e.source.index }
      end
      local save, bytes = CG.readSlot(t.to.version, t.to.slot)
      if not save then return self:say("Could not: " .. tostring(bytes)) end
      ok, why = CG.withDest(t.to.version, function(data)
        local a, b = PalPark.migrate({ save = save, data = data }, t.from.version, t.from.slot, picks)
        if not a then return a, b end
        CG.backup("pal_park_backups", t.to.version, t.to.slot, bytes)
        return require("src.core.SaveData").writeSlot(t.to.version, t.to.slot, save)
      end)
      local WHYS = { nationalDex = "That save needs the National Pokedex.",
                     parkFull = "That save's Pal Park already has six waiting.",
                     today = "Pokemon may migrate from that Game Pak only once a day." }
      if ok then self:say(("Six Pokemon migrated! Play the Catching Show at %s's Pal Park."):format(gameName(t.to.version)), 5)
      else self:say(WHYS[why] or ("Could not: " .. tostring(why)), 5) end
    else
      local T = require("src.world.Gen5PokeTransfer")
      local picks = {}
      for i, m in ipairs(t.picks) do
        picks[i] = m.kind == "walker" and { walker = m.walker, entry = m.entry } or { source = m.e.source, raw = m.e.raw }
      end
      ok, why = T.stage(t.to.version, t.to.slot, picks)
      if ok then self:say(("Six Pokemon are waiting at the Poke Transfer Lab in %s!"):format(gameName(t.to.version)), 5)
      else self:say("Could not: " .. tostring(why), 5) end
    end
    if ok then
      self.st = W.load()
      reset(self, true)
    end
  end

  -- a row of chips; returns the height used
  local function chips(self, f, x, y, w, items, current, onPick)
    local g = love.graphics
    local bh = f.body:getHeight() + 18
    local cx, cy = x, y
    g.setFont(f.body)
    if #items == 0 then
      setc(DIM); g.printf("None yet -- play and save that game first.", x + 4, y + 8, w - 8)
      return bh
    end
    for _, it in ipairs(items) do
      local label = it.text
      local cw = math.min(w, f.body:getWidth(label) + 36)
      if cx + cw > x + w and cx > x then cx = x; cy = cy + bh + 10 end
      local item = it
      self:button(cx, cy, cw, bh, label, function() onPick(item) end, current == it.key and "accent" or nil, f.body)
      cx = cx + cw + 10
    end
    return cy + bh - y
  end

  local function heading(f, x, y, text)
    local g = love.graphics
    g.setFont(f.head); setc(GOLD)
    g.print(text, x, y)
    return f.head:getHeight() + 8
  end

  function P:pageTransfer(x, y, w, h, f)
    local g = love.graphics
    local t = tx(self)
    local y0 = y
    -- the mode
    y = y + heading(f, x, y, "Transfer")
    local modes = {}
    for _, id in ipairs({ "palpark", "transfer" }) do modes[#modes + 1] = { key = id, text = M.MODES[id].label } end
    y = y + chips(self, f, x, y, w, modes, t.mode, function(it)
      if it.key ~= t.mode then self.tx = { mode = it.key, picks = {} } end
    end) + 10
    g.setFont(f.small); setc(DIM)
    local about = t.mode == "palpark"
      and "Six Pokemon from a Game Boy Advance game move to a DS game's Pal Park, where you catch them in the Catching Show. They cannot go back."
      or "Six Pokemon from a DS game wait at Black and White's Poke Transfer Lab on Route 15, where you catch them with the slingshot. They cannot go back. No held items, Eggs or HM moves."
    g.printf(about, x + 4, y, w - 8)
    local _, lines = f.small:getWrap(about, w - 8)
    y = y + #lines * f.small:getHeight() + 12
    -- from / to
    local mode = M.MODES[t.mode]
    local from = {}
    for _, s in ipairs(saves(mode.from)) do
      from[#from + 1] = { key = s.version .. "/" .. s.slot, text = ("%s - %s"):format(gameName(s.version), s.label), s = s }
    end
    y = y + heading(f, x, y, "From")
    y = y + chips(self, f, x, y, w, from, t.from and (t.from.version .. "/" .. t.from.slot), function(it)
      t.from, t.picks, t.list, t.armed = it.s, {}, nil, nil
    end) + 12
    local to = {}
    for _, s in ipairs(saves(mode.to)) do
      to[#to + 1] = { key = s.version .. "/" .. s.slot, text = ("%s - %s"):format(gameName(s.version), s.label), s = s }
    end
    y = y + heading(f, x, y, "To")
    y = y + chips(self, f, x, y, w, to, t.to and (t.to.version .. "/" .. t.to.slot), function(it)
      t.to, t.armed = it.s, nil
    end) + 12
    -- the six
    y = y + heading(f, x, y, ("Choose six  (%d/6)"):format(#t.picks))
    local items = list(self, t)
    if #items == 0 then
      g.setFont(f.body); setc(DIM)
      g.printf(t.from and "No Pokemon in that save's PC." or "Choose where they come from.", x + 4, y, w - 8)
      y = y + f.body:getHeight() + 16
    else
      local cell = 112
      local n = math.max(1, math.floor((w + 10) / (cell + 10)))
      for i, m in ipairs(items) do
        local cx, cy = x + ((i - 1) % n) * (cell + 10), y + math.floor((i - 1) / n) * (cell + 10)
        local on = picked(t, m)
        card(cx, cy, cell, cell, 12, on and { 0.18, 0.34, 0.28 } or (hovered(cx, cy, cell, cell) and { 0.18, 0.18, 0.24 }) or CARD, m.why and 0.5 or 0.9)
        if m.species then self:drawPortrait(m.species, cx + 24, cy + 6, cell - 48) end
        g.setFont(f.small); setc(m.why and DIM or INK)
        g.printf(("%s Lv%d"):format(m.name or "?", tonumber(m.level) or 1), cx + 4, cy + cell - f.small:getHeight() * 2 - 8, cell - 8, "center")
        setc(m.why and RED or (m.fromWalker and GOLD or DIM))
        g.printf(m.why and WHY[m.why] or (m.fromWalker and "Walker" or ""), cx + 4, cy + cell - f.small:getHeight() - 6, cell - 8, "center")
        local mm = m
        self:rect(cx, cy, cell, cell, function()
          if mm.why then return self:say(WHY[mm.why] or "Cannot transfer") end
          local at = picked(t, mm)
          if at then table.remove(t.picks, at) elseif #t.picks < 6 then t.picks[#t.picks + 1] = mm end
          t.armed = nil
        end)
      end
      y = y + math.ceil(#items / n) * (cell + 10) + 6
    end
    -- go
    local bh = f.body:getHeight() + 24
    local ready = t.from and t.to and #t.picks == 6
    local label = (not ready and "Choose a source, a destination and six Pokemon")
                  or (t.armed and "Tap again: they cannot be sent back") or "Transfer these six"
    self:button(x, y, math.min(w, 520), bh, label, function()
      if not ready then return end
      if not t.armed then t.armed = true return end
      t.armed = nil
      run(self, t)
    end, ready and "accent" or nil, f.body)
    y = y + bh + 12
    return y - y0
  end

  -- the tile's icon: two arrows passing
  local econIcon = P.econIcon
  function P.econIcon(id, cx, cy, r, tt)
    if id == "transfer" then
      local g = love.graphics
      g.setLineWidth(3)
      g.line(cx - r * 0.6, cy - r * 0.25, cx + r * 0.5, cy - r * 0.25)
      g.polygon("fill", cx + r * 0.6, cy - r * 0.25, cx + r * 0.35, cy - r * 0.45, cx + r * 0.35, cy - r * 0.05)
      setc(GOLD)
      g.line(cx + r * 0.6, cy + r * 0.25, cx - r * 0.5, cy + r * 0.25)
      g.polygon("fill", cx - r * 0.6, cy + r * 0.25, cx - r * 0.35, cy + r * 0.05, cx - r * 0.35, cy + r * 0.45)
      g.setLineWidth(1)
      return true
    end
    return econIcon and econIcon(id, cx, cy, r, tt) or false
  end
end

return M
