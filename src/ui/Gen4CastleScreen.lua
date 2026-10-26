-- THE BATTLE CASTLE'S TWO APPS (src/applications/frontier/battle_castle/
-- self_app.c and opponent_app.c), as text menus in the apps' own words
-- (banks 199 and 201). What each choice costs and when it is refused is
-- src/script/Gen4BattleCastle.lua's; this screen only asks.
--
--   self      your three: HEAL (HP / PP / both, by healing rank), RENTAL
--             (Berries, and items from rental rank 2), SUMMARY, MOVES, and
--             the two RANK UPs
--   opponent  their three, a Poke Ball until identified: CHECK (1 CP),
--             LEVEL +5 / -5 (1 / 15 CP), SUMMARY -- stats (2 CP) and, from
--             information rank 2, moves (5 CP) -- and RANK UP
--
-- B backs out a level; EXIT (or B on the Pokemon) closes the app.
-- opts = { mode = "self" | "opponent", castle, onDone }

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Gen4Text = require("src.import.Gen4Text")

local S = {}
S.__index = S
S.isOpaque = true
-- the two menus' words: Platinum's banks 199 / 201, HeartGold /
-- SoulSilver's 31 / 33 -- read by family
S.BANKS = { platinum = { SELF_BANK = 199, OPP_BANK = 201 }, hgss = { SELF_BANK = 31, OPP_BANK = 33 } }
setmetatable(S, { __index = function(_, k)
  local okB, Bands = pcall(require, "src.import.Gen4ScriptBands")
  return S.BANKS[(okB and Bands.family == "hgss") and "hgss" or "platinum"][k]
end })

function S:uiSize() return 256, 192 end
function S:wantsFillScale() return true end

local function B() return require("src.script.Gen4BattleCastle") end

function S.new(game, opts)
  local self = setmetatable({ game = game, data = game.data, mode = opts.mode, castle = opts.castle,
    onDone = opts.onDone, pages = {} }, S)
  self:push(self:root())
  return self
end

-- a line of one of the two banks, its {STRVAR}s filled from `...` (slot 0 first)
function S:say(bank, n, ...)
  Gen4Text.buffer(self.game, ...)
  return (Gen4Text.resolve(self.data, bank, n, self.game) or ""):gsub("\n", " ")
end
-- HGSS blanks the self app's SUMMARY / MOVES / YES / NO (its buttons are
-- drawn), so a blank line falls back to `alt` -- another line, or a string
function S:label(bank, n, alt)
  local s = self:say(bank, n)
  if s:match("%S") then return s end
  return type(alt) == "function" and alt() or alt
end
function S:bank() return (self.mode == "self") and S.SELF_BANK or S.OPP_BANK end

local function speciesName(data, sp)
  local def = data.pokemon and data.pokemon[sp]
  return def and def.name or tostring(sp)
end
function S:monName(mon) return mon and (mon.nickname or speciesName(self.data, mon.species)) or "?" end
function S:itemName(id)
  local it = id and self.data.items and self.data.items[id]
  return it and it.name or ""
end
function S:moveName(id)
  local m = self.data.moves and self.data.moves[id]
  return m and m.name or tostring(id)
end

-- ----------------------------------------------------------------- pages --

function S:push(p) p.cursor = p.cursor or 1; self.pages[#self.pages + 1] = p end
function S:pop() self.pages[#self.pages] = nil end
function S:top() return self.pages[#self.pages] end

function S:message(text, after)
  self:push({ kind = "msg", text = text, after = after })
end
-- a yes / no on `text`; `yes` runs on YES
function S:confirm(text, yes)
  self:push({ kind = "list", text = text, items = {
    { label = self:label(S.SELF_BANK, 30, Strings("YES")), fn = function() self:pop(); yes() end },
    { label = self:label(S.SELF_BANK, 31, Strings("NO")), fn = function() self:pop() end },
  } })
end
-- a purchase's answer: refused for want of CP (or rank), or done
function S:outcome(ok, reason, done, refusals)
  if ok then
    Sound.play(self.data, "Press_AB")
    if done then self:message(done) end
  else
    self:message((refusals and refusals[reason]) or self:say(self:bank(), (self.mode == "self") and 32 or 28))
  end
end

function S:members()
  local f = self.castle
  return (self.mode == "self") and (f.team or {}) or (f.opponentParty or {})
end

function S:root()
  local items = {}
  for i, mon in ipairs(self:members()) do
    items[i] = { mon = i, fn = function() self:push(self:monMenu(i)) end }
    local _ = mon
  end
  items[#items + 1] = { label = self:say(self:bank(), (self.mode == "self") and 6 or 5), fn = function() self:close() end }
  return { kind = "list", text = self:say(self:bank(), (self.mode == "self") and 5 or 4), items = items, root = true }
end

function S:monMenu(i)
  local f = self.castle
  local b = B()
  local mon = self:members()[i]
  if self.mode == "self" then
    return { kind = "list", text = self:say(S.SELF_BANK, 14), items = {
      { label = self:say(S.SELF_BANK, 9), fn = function() self:push(self:healMenu(i)) end },
      { label = self:say(S.SELF_BANK, 10), fn = function() self:push(self:rentalMenu(i)) end },
      { label = self:label(S.SELF_BANK, 11, function() return self:say(S.OPP_BANK, 33) end), fn = function() self:push(self:summary(mon, true)) end },
      { label = self:label(S.SELF_BANK, 12, function() return self:say(S.OPP_BANK, 34) end), fn = function() self:push(self:moves(mon)) end },
      { label = self:say(S.SELF_BANK, 13), fn = function() self:pop() end },
    } }
  end
  return { kind = "list", text = self:say(S.OPP_BANK, 12), items = {
    { label = self:say(S.OPP_BANK, 8), fn = function()
        if f.identity[i] then
          self:message(self:say(S.OPP_BANK, 20, self:monName(mon)))
        else
          self:confirm(self:say(S.OPP_BANK, 16, b.COST_IDENTITY), function()
            local ok, why = b.reveal(f, i)
            self:outcome(ok, why, self:say(S.OPP_BANK, 20, self:monName(mon)))
          end)
        end
      end },
    { label = self:say(S.OPP_BANK, 9), fn = function() self:push(self:levelMenu(i)) end },
    { label = self:say(S.OPP_BANK, 10), fn = function() self:push(self:infoMenu(i)) end },
    { label = self:say(S.OPP_BANK, 11), fn = function() self:pop() end },
  } }
end

function S:healMenu(i)
  local f, b = self.castle, B()
  local items = {}
  for opt = 1, 3 do
    items[opt] = { label = self:say(S.SELF_BANK, 18 + opt), dim = b.rank(f.save, f.challengeType, b.RANK_HEALING) < b.HEAL_RANK[opt],
      fn = function()
        self:confirm(self:say(S.SELF_BANK, 55, b.HEAL_COST[opt]), function()
          local ok, why = b.heal(f, i, opt)
          self:outcome(ok, why, self:say(S.SELF_BANK, 33 + opt, self:monName(f.team[i])),
            { rank = self:say(S.SELF_BANK, 33), nobenefit = self:say(S.SELF_BANK, 37) })
        end)
      end }
  end
  items[4] = { label = self:say(S.SELF_BANK, 22), fn = function() self:rankUp(b.RANK_HEALING, 42) end }
  items[5] = { label = self:say(S.SELF_BANK, 23), fn = function() self:pop() end }
  return { kind = "list", text = self:say(S.SELF_BANK, 24), items = items }
end

-- RANK UP: the gain message by the rank reached (sRankUpMessages)
function S:rankUp(kind, firstMsg)
  local f, b = self.castle, B()
  local rank = b.rank(f.save, f.challengeType, kind)
  if rank >= b.RANK_MAX[kind] then
    self:message(self:say(self:bank(), (self.mode == "self") and 27 or 40))
    return
  end
  local name = (f.save.player and f.save.player.name) or ""
  local q = (self.mode == "self") and self:say(S.SELF_BANK, 38, b.RANK_UP_COST[kind][rank + 1])
                                   or self:say(S.OPP_BANK, 76, b.RANK_UP_COST[kind][rank + 1])
  self:confirm(q, function()
    local ok, why = b.rankUp(f, kind)
    local gained = self:say(self:bank(), firstMsg + rank - 1, nil, nil, nil, nil, nil, name)
    self:outcome(ok, why, gained)
  end)
end

function S:rentalMenu(i)
  local f, b = self.castle, B()
  local function list(kind)
    local items = {}
    for k, r in ipairs(b.rentals(f, kind)) do
      items[k] = { label = ("%s  %d CP"):format(self:itemName(r.item), r.price), fn = function()
        local mon = f.team[i]
        local function buy()
          self:confirm(self:say(S.SELF_BANK, 55, r.price), function()
            local ok, why = b.rent(f, i, r.item, r.price)
            self:outcome(ok, why, self:say(S.SELF_BANK, 59, self:monName(mon), self:itemName(r.item)))
          end)
        end
        if mon and mon.item then
          self:message(self:say(S.SELF_BANK, 60, self:monName(mon), self:itemName(mon.item)), function()
            self:confirm(self:say(S.SELF_BANK, 61), buy)
          end)
        else
          buy()
        end
      end }
    end
    items[#items + 1] = { label = self:say(S.SELF_BANK, 47), fn = function() self:pop() end }
    return { kind = "list", text = self:say(S.SELF_BANK, (kind == "berries") and 48 or 49), items = items, scroll = true }
  end
  local rank = b.rank(f.save, f.challengeType, b.RANK_RENTALS)
  return { kind = "list", text = self:say(S.SELF_BANK, 15), items = {
    { label = self:say(S.SELF_BANK, 44), fn = function() self:push(list("berries")) end },
    { label = self:say(S.SELF_BANK, 45), dim = rank < b.ITEMS_RANK, fn = function()
        if rank < b.ITEMS_RANK then self:message(self:say(S.SELF_BANK, 54)) else self:push(list("items")) end
      end },
    { label = self:say(S.SELF_BANK, 46), fn = function() self:rankUp(b.RANK_RENTALS, 68) end },
    { label = self:say(S.SELF_BANK, 47), fn = function() self:pop() end },
  } }
end

function S:levelMenu(i)
  local f, b = self.castle, B()
  local function adjust(adj)
    local cost = (adj == b.ADJ_UP) and b.COST_LEVEL_UP or b.COST_LEVEL_DOWN
    if (f.levelAdj[i] or 0) == adj then
      self:message(self:say(S.OPP_BANK, (adj == b.ADJ_UP) and 29 or 30))
      return
    end
    self:confirm(self:say(S.OPP_BANK, 25, cost), function()
      local ok, why = b.adjustLevel(f, i, adj)
      self:outcome(ok, why, self:say(S.OPP_BANK, (adj == b.ADJ_UP) and 31 or 32))
    end)
  end
  return { kind = "list", text = self:say(S.OPP_BANK, 21, self:monName(f.opponentParty[i])), items = {
    { label = self:say(S.OPP_BANK, 22), fn = function() adjust(b.ADJ_UP) end },
    { label = self:say(S.OPP_BANK, 23), fn = function() adjust(b.ADJ_DOWN) end },
    { label = self:say(S.OPP_BANK, 24), fn = function() self:pop() end },
  } }
end

function S:infoMenu(i)
  local f, b = self.castle, B()
  local mon = f.opponentParty[i]
  return { kind = "list", text = self:say(S.OPP_BANK, 37), items = {
    { label = self:say(S.OPP_BANK, 33), fn = function()
        if f.statsUnlocked[i] then self:push(self:summary(mon)) return end
        self:confirm(self:say(S.OPP_BANK, 43, b.COST_STATS), function()
          local ok, why = b.unlockStats(f, i)
          self:outcome(ok, why, self:say(S.OPP_BANK, 47), { cp = self:say(S.OPP_BANK, 46) })
        end)
      end },
    { label = self:say(S.OPP_BANK, 34), dim = b.rank(f.save, f.challengeType, b.RANK_SUMMARY) < 2, fn = function()
        if b.rank(f.save, f.challengeType, b.RANK_SUMMARY) < 2 then self:message(self:say(S.OPP_BANK, 42)) return end
        if f.movesUnlocked[i] then self:push(self:moves(mon)) return end
        self:confirm(self:say(S.OPP_BANK, 66, b.COST_MOVES), function()
          local ok, why = b.unlockMoves(f, i)
          self:outcome(ok, why, self:say(S.OPP_BANK, 70), { cp = self:say(S.OPP_BANK, 69) })
        end)
      end },
    { label = self:say(S.OPP_BANK, 35), fn = function() self:rankUp(b.RANK_SUMMARY, 80) end },
    { label = self:say(S.OPP_BANK, 36), fn = function() self:pop() end },
  } }
end

-- the stat page: item, nature, ability, the five stats
function S:summary(mon, own)
  local data = self.data
  local def = mon and require("src.pokemon.Gen4Forms").definition(data, mon)
  local ability = def and def.abilities and def.abilities[mon.abilitySlot or 1]
  local ab = ability and data.abilities and data.abilities[ability]
  local st = mon and mon.stats or {}
  local lines = {
    ("%s  Lv%d"):format(self:monName(mon), mon and mon.level or 0),
    ("Item: %s"):format(self:itemName(mon and mon.item)),
    ("Nature: %s"):format(tostring(mon and mon.nature or "")),
    ("Ability: %s"):format(ab and ab.name or tostring(ability or "")),
    ("HP %d/%d"):format(mon and mon.hp or 0, st.hp or 0),
    ("Atk %d  Def %d  Spe %d"):format(st.attack or 0, st.defense or 0, st.speed or 0),
    ("SpA %d  SpD %d"):format(st.spatk or 0, st.spdef or 0),
  }
  local _ = own
  return { kind = "panel", lines = lines }
end
function S:moves(mon)
  local lines = { self:monName(mon) }
  local P = require("src.pokemon.Pokemon")
  for _, m in ipairs(mon and mon.moves or {}) do
    lines[#lines + 1] = ("%s  %d/%d"):format(self:moveName(m.id), m.pp or 0, P.maxPP(self.data.moves and self.data.moves[m.id], m))
  end
  return { kind = "panel", lines = lines }
end

function S:close()
  if self.closed then return end
  self.closed = true
  if self.game.stack:top() == self then self.game.stack:pop() end
  if self.onDone then self.onDone() end
end

-- ----------------------------------------------------------------- input --

function S:update()
  local input = self.game.input
  if not input or self.closed then return end
  local p = self:top()
  if not p then self:close() return end
  if p.kind == "msg" or p.kind == "panel" then
    if input:wasPressed("a") or input:wasPressed("b") then
      self:pop()
      if p.after then p.after() end
    end
    return
  end
  local n = #p.items
  if input:wasPressed("up") then p.cursor = (p.cursor - 2) % n + 1; Sound.play(self.data, "Select")
  elseif input:wasPressed("down") then p.cursor = p.cursor % n + 1; Sound.play(self.data, "Select")
  elseif input:wasPressed("a") then
    Sound.play(self.data, "Press_AB")
    local it = p.items[p.cursor]
    if it and it.fn then it.fn() end
  elseif input:wasPressed("b") then
    if p.root then self:close() else self:pop() end
  end
end

-- ------------------------------------------------------------------ draw --

function S:draw()
  local g = love.graphics
  local f, b = self.castle, B()
  g.setColor(0.32, 0.14, 0.18, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  -- the header: who and their CP
  g.setColor(1, 1, 1, 1)
  Font.drawBox(0, 0, 32, 4)
  g.setColor(0, 0, 0, 1)
  Font.draw((f.save.player and f.save.player.name) or "", 8, 8)
  Font.draw(("%d CP"):format(b.cp(f.save, f.challengeType)), 176, 8)
  -- the three
  for i, mon in ipairs(self:members()) do
    local x = 8 + (i - 1) * 82
    local known = self.mode == "self" or f.identity[i]
    g.setColor(0, 0, 0, 1)
    if known then
      g.setColor(1, 1, 1, 1)
      Font.draw(self:monName(mon), x, 40)
      Font.draw(("Lv%d"):format(mon.level or 0), x, 52)
      Font.draw(("%d/%d"):format(mon.hp or 0, mon.stats and mon.stats.hp or 0), x, 64)
      if mon.item then Font.draw(self:itemName(mon.item), x, 76) end
      if self.mode == "opponent" and (f.levelAdj[i] or 0) ~= 0 then
        Font.draw((f.levelAdj[i] == b.ADJ_UP) and "+5" or "-5", x + 56, 52)
      end
    else
      g.setColor(1, 1, 1, 1)
      Font.draw("?", x + 24, 52)
    end
  end
  g.setColor(1, 1, 1, 1)
  local p = self:top()
  if not p then return end
  if p.kind == "panel" then
    Font.drawBox(0, 11, 32, 13)
    g.setColor(0, 0, 0, 1)
    for k, line in ipairs(p.lines) do Font.draw(line, 8, 96 + (k - 1) * 12) end
  else
    -- the message along the bottom, the list to the right above it
    Font.drawBox(0, 18, 32, 6)
    g.setColor(0, 0, 0, 1)
    Font.draw(p.text or "", 8, 152)
    if p.kind == "list" then
      local rows, first = math.min(#p.items, 6), 1
      if p.cursor > rows then first = p.cursor - rows + 1 end
      g.setColor(1, 1, 1, 1)
      Font.drawBox(16, 18 - rows * 2 - 2, 16, rows * 2 + 2)
      for r = 0, rows - 1 do
        local it = p.items[first + r]
        if it then
          local label = it.label or self:monName(self:members()[it.mon])
          if it.mon and self.mode == "opponent" and not f.identity[it.mon] then label = "?" end
          if it.dim then g.setColor(0.55, 0.55, 0.55, 1) else g.setColor(0, 0, 0, 1) end
          Font.draw(((first + r == p.cursor) and "> " or "  ") .. label, 136, 144 - rows * 16 + r * 16)
        end
      end
    end
  end
  g.setColor(1, 1, 1, 1)
end

return S
