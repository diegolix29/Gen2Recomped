-- THE BATTLE DOME'S TOURNEY TREE AND OPPONENT CARD (battle_dome.c's
-- Task_ShowTourneyTree / Task_ShowTourneyInfoCard), as plain text.
--
--   tree      the sixteen in bracket order, two columns (the cartridge's left
--             and right halves), each name with the round it went out in
--   opponent  the next opponent's name, seed and three Pokemon
--
-- A or B closes it. opts = { mode = "tree" | "opponent", ctx, onDone }

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local S = {}
S.__index = S
S.isOpaque = true

-- sTourneyTreeTrainerIds: the seeds top to bottom, left half then right
S.TREE = { 0, 15, 8, 7, 3, 12, 11, 4, 1, 14, 9, 6, 2, 13, 10, 5 }

function S.new(game, opts)
  return setmetatable({ game = game, data = game.data, mode = opts.mode, ctx = opts.ctx, onDone = opts.onDone }, S)
end

function S:update()
  local input = self.game.input
  if not input or self.closed then return end
  if input:wasPressed("a") or input:wasPressed("b") then
    Sound.play(self.data, "Press_AB")
    self.closed = true
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

local ROUND = { [0] = "R1", "R2", "SF", "F" }

function S:draw()
  local g = love.graphics
  local D = require("src.script.Gen3BattleDome")
  local _, d = D.state(self.game.save)
  g.setColor(0.18, 0.24, 0.42, 1)
  g.rectangle("fill", 0, 0, 240, 160)
  g.setColor(1, 1, 1, 1)
  if self.mode == "opponent" then
    local t = D.tournamentId(d, d.opponentId)
    Font.drawBox(0, 0, 30, 20)
    g.setColor(0, 0, 0, 1)
    Font.draw(Strings("Next opponent: %s", D.name(self.ctx, d.opponentId)), 8, 8)
    Font.draw(Strings("Seed %d", (t or 0) + 1), 8, 24)
    local list = {}
    if d.opponentId == D.BRAIN then
      for i, m in ipairs(D.TUCKER[d.brainTeam or 0]) do list[i] = m.species end
    elseif t and d.mons[t] then
      local p = require("src.script.Gen3BattleFrontier").parties(self.data)
      for i, id in ipairs(d.mons[t]) do list[i] = p and p.mons[id] and p.mons[id].species end
    end
    for i, sp in ipairs(list) do
      local def = self.data.pokemon and self.data.pokemon[sp]
      Font.draw(def and def.name or tostring(sp), 16, 40 + i * 16)
    end
  else
    for col = 0, 1 do
      for row = 1, 8 do
        local seed = S.TREE[col * 8 + row]
        local tr = d.trainers[seed]
        if tr then
          local name = D.name(self.ctx, tr.trainerId)
          local tag = tr.eliminated and ("x" .. (ROUND[tr.at] or "")) or ""
          if tr.trainerId == D.PLAYER then g.setColor(1, 0.9, 0.4, 1) else g.setColor(1, 1, 1, 1) end
          Font.draw(("%s %s"):format(name, tag), 4 + col * 120, 4 + (row - 1) * 18)
        end
      end
    end
  end
  g.setColor(1, 1, 1, 1)
end

return S
