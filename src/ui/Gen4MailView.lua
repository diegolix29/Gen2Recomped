-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S MAIL READER, in the mode the bag opens it in.
--
-- UseMailFromMenu -> FieldSystem_LaunchMailApp_Read(MAIL_CONTEXT_CHECK):
-- a blank letter of the Mail's own design (Gen4MailGra), nothing written on
-- it and no Pokemon icons; MailViewer_HandleInput_Read closes it on A or B
-- with SEQ_SE_DP_PIRORIRO2.  Read mode draws no buttons (the interface screen
-- is the write mode's).  The top screen is the stationery, the bottom screen
-- its plain fill.

local Assets = require("src.render.Assets")

local V = {}
V.__index = V
V.isOpaque = true

local W, H = 256, 192
function V:uiSize() return W, H end
function V:wantsFillScale() return true end

-- `mailType` 0..11 (item 137..148 minus 137, Item_GetMailType)
function V.new(game, mailType, onDone)
  local rec = game.data and game.data.gen4_mail_gra
  local design = rec and rec.designs and rec.designs[(tonumber(mailType) or 0) + 1]
  local self = setmetatable({ game = game, design = design, onDone = onDone, frame = 0 }, V)
  local function img(entry)
    if not (entry and entry.path) then return nil end
    local ok, i = pcall(Assets.image, entry.path)
    if ok and i then i:setFilter("nearest", "nearest") end
    return ok and i or nil
  end
  self.top = design and img(design.top)
  self.sub = design and img(design.sub)
  return self
end

function V.available(game, mailType)
  local rec = game and game.data and game.data.gen4_mail_gra
  local d = rec and rec.designs and rec.designs[(tonumber(mailType) or 0) + 1]
  return d and d.top ~= nil
end

function V:update()
  if self.closed then return end
  self.frame = self.frame + 1
  local input = self.game.input
  if input and (input:wasPressed("a") or input:wasPressed("b")) then
    self.closed = true
    local G = self.game
    pcall(function()
      local Sound = require("src.core.Sound")
      if not Sound.playSe(G.data, "SEQ_SE_DP_PIRORIRO2") then Sound.play(G.data, "Press_AB") end
    end)
    if G.stack:top() == self then G.stack:pop() end
    if self.onDone then self.onDone() end
  end
end

-- the top screen; in a dual-screen layout the renderer asks for the sub one
function V:draw()
  local g = love.graphics
  g.clear(0, 0, 0, 1)
  g.setColor(1, 1, 1, 1)
  if self.top then g.draw(self.top, 0, 0) end
end

function V:drawSub()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  if self.sub then g.draw(self.sub, 0, 0) end
end

return V
