-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's TRAINER CARD, which was falling back to Kanto's.
--
-- Reported from play: "Gen4 bag is missing gen4 pokemon menu is missing gen4
-- options menu is missing and the trainer card as well they are falling back
-- to gen1 art".  OPTIONS was the first of those four to get a screen; this is
-- the second.
--
-- TWO PAGES, as the cartridge has: the card itself, and the BADGE CASE that A
-- flips to.  The badge case is the cartridge's own art and so are the badges
-- in it.  The card face is not, and that is said plainly below rather than
-- hidden behind something that looks close enough.
--
-- WHAT IS THE CARTRIDGE'S HERE:
--
--   * THE BADGE CASE SCREEN, `trainer_card/badge_case` -- the "LEAGUE BADGES"
--     panel with its eight empty sockets, composed from its own tilemap.
--   * THE EIGHT BADGES, `trainer_card/badge_case_sprites_00..07`.
--   * WHERE THE BADGES GO.  Measured off the panel rather than guessed: the
--     eight sockets are the only shapes on it darker than its own background,
--     and they come out at x = 43, 99, 155, 211 and y = 59, 115 -- a pitch of
--     56 both ways, four across and two down.  Each badge's art sits in the
--     top-left 40x40 of its 64x64 frame centred on (19.5, 19.5), so a badge
--     drawn twenty pixels up and left of a socket's centre lands in it.
--
-- WHAT IS NOT, and why:
--
--   * THE CARD FACE.  Platinum draws the card's own background and its field
--     labels as BACKGROUND TILES, and `trainer_card/trainer_card` is that
--     strip -- extracted, 64x240, and not composed, because nothing in that
--     archive pairs it with a tilemap the way the badge case is paired with
--     its own.  Until it is, the face is drawn in this port's own Gen 4 window
--     frame with the engine's words, and it is a PORT'S CARD rather than
--     Platinum's.
--   * THE PORTRAIT.  `trainer_card/lucas` and `trainer_card/dawn` are in the
--     cache at 256x256 and are likewise uncomposed tile sheets; drawing one
--     raw would put a field of scrambled tiles on the card, so nothing is
--     drawn there.
--
-- Neither of those is a guess waiting to be made -- both are one tilemap away,
-- and the tilemap is the thing to find.

local Badges = require("src.inventory.Badges")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local Gen4TrainerCard = {}
Gen4TrainerCard.__index = Gen4TrainerCard
Gen4TrainerCard.isOpaque = true

local W, H = 256, 192

-- The badge sockets, measured off `badge_case` itself.
local SOCKET_X = { 43, 99, 155, 211 }
local SOCKET_Y = { 59, 115 }
-- A badge's art is the top-left 40x40 of its 64x64 frame.
local BADGE_OFFSET = 20

-- The card face, in this port's own frame.
local CARD = { tx = 1, ty = 1, tw = 30, th = 15 }
local LABEL_X = 24
local VALUE_X = 150
local FIRST_ROW = 30
local ROW_PITCH = 18

function Gen4TrainerCard:uiSize() return W, H end
function Gen4TrainerCard:wantsFillScale() return true end
function Gen4TrainerCard:wantsEdgeBleed() return false end

function Gen4TrainerCard:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4TrainerCard.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4TrainerCard)
  self.game = game
  self.onCancel = opts.onCancel
  self.back = false
  self.cache = {}
  self.art = ((game.data or {}).gen4_graphics or {}).screens or {}
  if not self.art["trainer_card/badge_case"] then
    Logger.warn("gen4 trainer card: this cache carries no badge case art -- "
                .. "the badge page will be drawn in the engine's own frame")
  end
  return self
end

-- One of the cache's screen pictures, by the key the graphics stage files it
-- under.  The record is `{ path, width, height, ... }`; an older cache wrote a
-- bare path, which still resolves.
function Gen4TrainerCard:img(key)
  local rec = self.art[key]
  local path = (type(rec) == "table" and rec.path) or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

function Gen4TrainerCard:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4TrainerCard:update()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("a") then
    self.back = not self.back
  elseif input:wasPressed("b") or input:wasPressed("start") then
    if self.back then self.back = false else self:close() end
  end
end

-- The rows, in the order Platinum prints them.
function Gen4TrainerCard:rows()
  local save = self.game.save or {}
  local player = save.player or {}
  local owned = 0
  for _ in pairs((save.pokedex or {}).owned or {}) do owned = owned + 1 end
  local seconds = 0
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if ok and SaveData and SaveData.playSeconds then
    seconds = math.floor(SaveData.playSeconds(save) or 0)
  end
  local id = tonumber(player.id) or 0
  return {
    { Strings("NAME"), tostring(player.name or Strings("PLAYER")) },
    { Strings("IDNo."), ("%05d"):format(id % 100000) },
    { Strings("MONEY"), Strings("₽%d", math.floor(save.money or 0)) },
    { Strings("POKéDEX"), tostring(owned) },
    { Strings("TIME"),
      ("%d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60) },
  }
end

-- How many badges this save has, and which.  `Badges.list` is the dataset's
-- own order, so a hack that renames or reorders them still lines up.
function Gen4TrainerCard:earned()
  local out = {}
  for i, entry in ipairs(Badges.list(self.game.data) or {}) do
    if i <= 8 then out[i] = Badges.has(self.game.save, entry) and true or false end
  end
  return out
end

function Gen4TrainerCard:drawBadges()
  local g = love.graphics
  local panel = self:img("trainer_card/badge_case")
  if panel then
    g.setColor(1, 1, 1, 1)
    g.draw(panel, 0, 0)
  else
    Font.drawBox(CARD.tx, CARD.ty, CARD.tw, CARD.th)
    Font.draw(Strings("BADGES"), LABEL_X, 20)
  end

  local earned = self:earned()
  for i = 1, 8 do
    if earned[i] then
      local badge = self:img(("trainer_card/badge_case_sprites_%02d"):format(i - 1))
      if badge then
        local x = SOCKET_X[(i - 1) % 4 + 1]
        local y = SOCKET_Y[math.floor((i - 1) / 4) + 1]
        g.setColor(1, 1, 1, 1)
        g.draw(badge, x - BADGE_OFFSET, y - BADGE_OFFSET)
      end
    end
  end
end

function Gen4TrainerCard:drawFace()
  local g = love.graphics
  Font.drawBox(CARD.tx, CARD.ty, CARD.tw, CARD.th)
  local title = Strings("TRAINER CARD")
  Font.draw(title, math.floor((W - Font.width(title)) / 2), 14)

  local y = FIRST_ROW
  for _, row in ipairs(self:rows()) do
    Font.draw(row[1], LABEL_X, y)
    Font.draw(row[2], VALUE_X, y)
    y = y + ROW_PITCH
  end

  -- The badges along the bottom, small, so the front says at a glance how far
  -- the player has got.  A badge that has not been earned is not drawn, which
  -- is what the cartridge does -- there is no empty socket waiting on the card
  -- itself, only in the case.
  local earned = self:earned()
  local x = 24
  for i = 1, 8 do
    if earned[i] then
      local badge = self:img(("trainer_card/badge_case_sprites_%02d"):format(i - 1))
      if badge then
        g.setColor(1, 1, 1, 1)
        g.draw(badge, x - 4, H - 46, 0, 0.6, 0.6)
      end
    end
    x = x + 26
  end
  g.setColor(1, 1, 1, 1)
end

function Gen4TrainerCard:draw()
  local g = love.graphics
  g.setColor(0.10, 0.12, 0.18, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  if self.back then self:drawBadges() else self:drawFace() end
  g.setColor(1, 1, 1, 1)
end

return Gen4TrainerCard
