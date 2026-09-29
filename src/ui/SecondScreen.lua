-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SECOND SCREEN, and it is never a second window.
--
-- From the original brief: "Instead of having two screens for the poketch and
-- bottom screen allow users to switch between the two with a button or have the
-- choice of using a button to show the bottom screen in the top right corner
-- with a hotkey and change its size and interact with it there."
--
-- The game runs in ONE window, like every other version in this launcher, and
-- the player chooses how the bottom screen reaches them.  This module owns that
-- choice and nothing else: it answers WHERE the bottom screen is right now, in
-- the same 256x192 space every Gen 4 screen already draws in, and it wraps a
-- draw so a screen can be written once and appear in either place.
--
-- IT DOES NOT OWN THE STACK.  A screen that wants to be a bottom-screen screen
-- asks for the transform and draws itself; nothing here pushes, pops, or knows
-- what is on the stack.  That is deliberate: the alternative -- a manager that
-- decides which screens are "bottom screen" ones -- puts a second, invisible
-- stack next to the real one, and the first disagreement between them is a
-- screen that cannot be closed.
--
-- THE MODES
--
--   swap    the bottom screen takes the whole window when it is up.  Works at
--           any window size and on a phone, and the DS's own split costs
--           nothing here because the bottom screen is almost never needed
--           DURING an action -- it is a thing you stop to look at.
--   inset   a panel in the TOP-RIGHT corner over the main screen, raised and
--           lowered with a hotkey, interactive in place, and resizable.
--   off     Gen 1-3, and Gen 4 for a player who wants no second surface at
--           all.  Every caller degrades to drawing on the main screen.
--
-- NOTHING HERE IS REACHABLE FOR GEN 1-3 and no Gen 1-3 draw path gains a
-- branch: `SecondScreen.mode` returns "off" for them, and "off" is the case
-- every caller already has to handle.

local SecondScreen = {}

-- The DS's own screen, which is also the space every Gen 4 screen in this port
-- is written in -- so an inset panel is a scale of the picture and not a
-- different layout.
local W, H = 256, 192

SecondScreen.MODES = { "swap", "inset", "off" }

-- How big the inset panel is, as a fraction of the window.  The brief asks for
-- this to be adjustable, so it is a setting and not a constant; these are the
-- stops the options row cycles through.
SecondScreen.SCALES = { 0.35, 0.45, 0.55, 0.70 }
SecondScreen.DEFAULT_SCALE = 2          -- 0.45

-- How far the panel sits from the window's edge, in main-screen pixels.
local MARGIN = 6

local function options(game)
  return (game and game.save and game.save.options) or {}
end

-- Whether this cartridge has a second screen at all.  One question, asked in
-- one place, so no caller has to know how it is answered.
function SecondScreen.available(game)
  local data = game and game.data
  if data and data.isGen4Cache then return true end
  local ok, V = pcall(require, "src.core.GameVersion")
  if not ok then return false end
  if V.isDualScreen then
    local okDual, dual = pcall(V.isDualScreen, V.get())
    if okDual then return dual and true or false end
  end
  return (V.generation and V.generation(V.get()) == 4) and true or false
end

function SecondScreen.mode(game)
  if not SecondScreen.available(game) then return "off" end
  local mode = options(game).secondScreenMode
  for _, name in ipairs(SecondScreen.MODES) do
    if mode == name then return mode end
  end
  return "swap"
end

function SecondScreen.scale(game)
  local at = tonumber(options(game).secondScreenScale)
    or SecondScreen.DEFAULT_SCALE
  at = math.max(1, math.min(#SecondScreen.SCALES, math.floor(at)))
  return SecondScreen.SCALES[at], at
end

-- Where the bottom screen is, in main-screen pixels: x, y, and the scale its
-- own 256x192 is drawn at.  Nil when there is no second surface, which is the
-- caller's cue to draw on the main screen as usual.
function SecondScreen.rect(game)
  local mode = SecondScreen.mode(game)
  if mode == "off" then return nil end
  if mode == "swap" then return 0, 0, 1 end
  local scale = SecondScreen.scale(game)
  local w = W * scale
  return W - w - MARGIN, MARGIN, scale
end

-- Is the bottom screen currently up?  On `swap` it is whatever the player last
-- toggled; on `inset` the same, because the panel is raised and lowered with
-- the same hotkey.  Stored on the game rather than the save: which screen you
-- were looking at is not a thing to persist across a load.
function SecondScreen.raised(game)
  return game and game.secondScreenUp and true or false
end

function SecondScreen.toggle(game)
  if not game or SecondScreen.mode(game) == "off" then return false end
  game.secondScreenUp = not game.secondScreenUp
  return game.secondScreenUp
end

-- PUT AWAY, WHICH IS NOT THE SAME QUESTION AS `raised`.
--
-- `raised` is transient and belongs to whatever is on the bottom surface right
-- now: the Poketch sets it when it opens and clears it when it closes. That is
-- the right shape for a screen you open, and the WRONG shape for a screen that
-- is simply on -- a battle's menu is not something the player opens, it is
-- where the menu lives until they say otherwise.
--
-- So this is the player's standing answer to "do I want the bottom screen at
-- all", kept in the SAVE rather than on the session because it is a preference
-- and not a state. `mode == "off"` is still the stronger statement -- no second
-- surface ever; this one is "not just now".
--
-- The two must not be folded together. They were, briefly, and the bug that
-- came out of it is worth remembering: a player who had opened the Poketch
-- once in the field left `secondScreenUp` false behind them, and every battle
-- afterwards came up with the menu stowed for no reason they could see.
function SecondScreen.stowed(game)
  if SecondScreen.mode(game) == "off" then return true end
  return options(game).secondScreenStowed and true or false
end

function SecondScreen.stow(game, away)
  if not (game and game.save and game.save.options) then return false end
  if SecondScreen.mode(game) == "off" then return true end
  game.save.options.secondScreenStowed = away and true or nil
  return SecondScreen.stowed(game)
end

function SecondScreen.toggleStow(game)
  return SecondScreen.stow(game, not SecondScreen.stowed(game))
end

-- Run `body` with the coordinate system moved onto the bottom screen.
--
-- The transform is pushed and popped around the call rather than left for the
-- caller to undo, because a screen that forgets to undo it moves everything
-- drawn after it -- including screens that have nothing to do with this one.
function SecondScreen.draw(game, body)
  local x, y, scale = SecondScreen.rect(game)
  local g = love.graphics
  if not x then return body() end
  g.push()
  g.translate(x, y)
  g.scale(scale, scale)
  local ok, err = pcall(body)
  g.pop()
  if not ok then error(err, 0) end
end

-- The panel's own frame, drawn around an inset so it reads as a second screen
-- rather than as part of the first.  Nothing on `swap`, where the bottom screen
-- IS the window.
function SecondScreen.drawFrame(game)
  local x, y, scale = SecondScreen.rect(game)
  if not x or scale >= 1 then return end
  local g = love.graphics
  local w, h = W * scale, H * scale
  g.setColor(0, 0, 0, 0.55)
  g.rectangle("fill", x - 2, y - 2, w + 4, h + 4)
  g.setColor(0.80, 0.84, 0.92, 1)
  g.rectangle("line", x - 1.5, y - 1.5, w + 3, h + 3)
  g.setColor(1, 1, 1, 1)
end

-- POINTER ROUTING.  A click inside the panel belongs to the bottom screen and
-- must arrive there in the BOTTOM SCREEN's coordinates, not the window's --
-- which is the whole of "interact with it there".  Returns nil when the point
-- is not the second screen's, so a caller can fall through to the field.
function SecondScreen.toLocal(game, px, py)
  local x, y, scale = SecondScreen.rect(game)
  if not x or not SecondScreen.raised(game) then return nil end
  local lx, ly = (px - x) / scale, (py - y) / scale
  if lx < 0 or ly < 0 or lx >= W or ly >= H then return nil end
  return lx, ly
end

function SecondScreen.contains(game, px, py)
  return SecondScreen.toLocal(game, px, py) ~= nil
end

return SecondScreen
