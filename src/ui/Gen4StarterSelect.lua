-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Professor Rowan's briefcase, which is the first 3D this port draws itself.
--
-- Everything on this screen is the cartridge's own: `psel_all` out of
-- `ev_pokeselect` is one model holding the case, its lid, the three Poke Balls
-- and their shadows; the animation of the same name is 41 frames over its 12
-- joints, and it is what opens the case and tips the balls out in front of it.
-- The words are message bank 360 and the three species are the ones
-- `choose_starter_app.c` names.
--
-- WHAT THIS FILE INVENTS, said here so it is never mistaken for extracted
-- data, and it is now a much shorter list than it was:
--
--   * THE LIFT ON THE SELECTED BALL.  The cartridge has a 73-frame animation
--     per ball for this and they are extracted; what it does with them is app
--     code rather than data, so this raises the chosen one instead.
--   * THE CAMERA.  Distance and pitch are chosen to frame the posed model;
--     the cartridge's camera comes from its own movement steps.
--
-- AND WHAT USED TO BE HERE.  An earlier version of this screen placed the
-- three balls itself -- a spread measured off the case's inside floor, evenly
-- divided, with the middle ball level with the others.  All of that was wrong,
-- and wrong in a way no amount of measuring the case could have fixed: the
-- positions are in the model's NODE transforms, which this engine did not read
-- until now.  The cartridge puts them at x = -30, 0 and +30 with the middle
-- one 6 units nearer the floor, and the animation then moves all three.

local Font = require("src.render.Font")
local Gen4Anim = require("src.import.Gen4Anim")
local Gen4Model = require("src.render.Gen4Model")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen4StarterSelect = {}
Gen4StarterSelect.__index = Gen4StarterSelect
Gen4StarterSelect.isOpaque = true

local W, H = 256, 192

-- The message box, in tiles: full width, at the bottom, as every Gen 4 line is.
local BOX = { tx = 0, ty = 16, tw = 32, th = 8 }
local TEXT_X = (BOX.tx + 2) * 8
local TEXT_Y = (BOX.ty + 1) * 8 + 4
local LINE_H = 14

-- THE MODEL IS Z-UP.  `psel_all` was exported with the vertical axis last --
-- its lid reaches y = 116 in what the case model calls depth -- while the
-- engine's camera assumes y is up.  This is the rotation between them, applied
-- to the scene rather than to the geometry so the cartridge's numbers stay the
-- cartridge's numbers.
local Z_UP_TO_Y_UP = {
  1, 0, 0, 0,
  0, 0, 1, 0,
  0, -1, 0, 0,
  0, 0, 0, 1,
}

local CAMERA_PITCH = 0.55
local CAMERA_DISTANCE = 1.15     -- multiplied by the posed model's own extent
local SPIN_PER_FRAME = 0.004
local SELECTED_LIFT = 12.0
local FRAME_STEP = 1             -- animation frames per engine frame

function Gen4StarterSelect:uiSize() return W, H end
function Gen4StarterSelect:wantsFillScale() return true end
function Gen4StarterSelect:wantsEdgeBleed() return false end

function Gen4StarterSelect:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

local function multiply(a, b)
  local out = {}
  for row = 0, 3 do
    for col = 0, 3 do
      local sum = 0
      for k = 0, 3 do
        sum = sum + a[row * 4 + k + 1] * b[k * 4 + col + 1]
      end
      out[row * 4 + col + 1] = sum
    end
  end
  return out
end

local function apply(m, p)
  return {
    m[1] * p[1] + m[2] * p[2] + m[3] * p[3] + m[4],
    m[5] * p[1] + m[6] * p[2] + m[7] * p[3] + m[8],
    m[9] * p[1] + m[10] * p[2] + m[11] * p[3] + m[12],
  }
end

local function named(list, name)
  for _, item in ipairs(list or {}) do
    if item.name == name then return item end
  end
  return nil
end

function Gen4StarterSelect.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4StarterSelect)
  self.game = game
  self.onChoose = opts.onChoose
  self.onCancel = opts.onCancel
  self.index = 1
  self.spin = 0
  self.frame = 0
  self.phase = "opening"

  local data = game.data or {}
  self.lines = (data.gen4_menus or {}).starter or {}
  self.rows = self.lines.rows or {}

  local set = ((data.gen4_models or {}).sets or {}).starter
  if not set then
    -- A cache from before the models stage.  Saying so and closing is better
    -- than an empty screen the player cannot leave.
    Logger.warn("gen4 starter select: this cache carries no starter models")
    self.unavailable = true
    return self
  end

  local record = named(set.models, "psel_all")
  self.scene = Gen4Model.new(record)
  self.ground = Gen4Model.new(named(set.models, "pmsel_bg"))
  if not self.scene then
    Logger.warn("gen4 starter select: the briefcase model would not build")
    self.unavailable = true
    return self
  end

  -- Node index by name, so a ball can be found without counting.  The two
  -- nodes per ball -- `psel_mb_a` and `psel_mb_a_` -- are its body and its
  -- lid; both move together and both take the lift.
  self.ballNodes = {}
  for i, row in ipairs(self.rows) do
    local wanted = { [tostring(row.model)] = true, [tostring(row.model) .. "_"] = true }
    local found = {}
    for index, node in ipairs(record.nodes or {}) do
      if wanted[node.name] then found[#found + 1] = index - 1 end
    end
    self.ballNodes[i] = found
  end

  -- The animation that opens it, paired by NAME with the model rather than by
  -- position in the archive: the two sit in different members and nothing but
  -- the name says they belong together.
  local animation = named(set.animations, "psel_all")
  if animation and animation.tracks then
    self.tracks = {}
    for _, track in ipairs(animation.tracks) do
      self.tracks[track.index] = track
    end
    self.frames = animation.frames or 1
  else
    -- Extracted before the tracks existed.  The rest pose is the closed case,
    -- which is honest about what is missing rather than pretending.
    Logger.warn("gen4 starter select: this cache carries no opening animation")
    self.frames = 1
  end

  return self
end

-- Where every shape stands this frame: the animation's own matrices, with the
-- chosen ball raised.  Rebuilt only when something changed, because the walk
-- is cheap but not free and most frames change nothing.
function Gen4StarterSelect:poseNow()
  local key = ("%d/%d/%s"):format(self.frame, self.index, tostring(self.phase))
  if self.poseKey == key then return self.pose end

  local lifted = {}
  if self.phase ~= "opening" then
    for _, node in ipairs(self.ballNodes[self.index] or {}) do lifted[node] = true end
  end

  local tracks, frame = self.tracks, self.frame
  self.pose = self.scene:posed(function(node)
    local track = tracks and tracks[node]
    local m = track and Gen4Anim.unpackFrame(track.matrices, frame)
    if m and lifted[node] then
      -- Straight up in the model's own space, which is its third axis.
      m = { m[1], m[2], m[3], m[4],
            m[5], m[6], m[7], m[8],
            m[9], m[10], m[11], m[12] + SELECTED_LIFT,
            0, 0, 0, 1 }
    end
    return m
  end)
  self.poseKey = key
  return self.pose
end

-- ------------------------------------------------------------------- text --

function Gen4StarterSelect:pagesOf(text)
  if type(text) ~= "string" or text == "" then return { "" } end
  -- The cartridge's colour codes pick a palette row this port does not have a
  -- text style for yet; dropped rather than printed as `{COLOR 3}`.
  text = text:gsub("{COLOR %d+}", "")
  local pages = {}
  for page in (text .. "\r"):gmatch("([^\r\f]*)[\r\f]") do
    page = page:gsub("^%s+", ""):gsub("%s+$", "")
    if page ~= "" then pages[#pages + 1] = page end
  end
  if #pages == 0 then pages[1] = "" end
  return pages
end

function Gen4StarterSelect:say(text)
  self.pages = self:pagesOf(text)
  self.page = 1
end

function Gen4StarterSelect:currentText()
  if self.phase == "opening" or self.phase == "intro" then return self.lines.intro end
  if self.phase == "choosing" then return self.lines.choose end
  local row = self.rows[self.index]
  return row and row.offer or ""
end

-- ------------------------------------------------------------------- flow --

function Gen4StarterSelect:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4StarterSelect:confirm()
  local row = self.rows[self.index]
  if not row then return end
  self.game.stack:pop()
  if self.onChoose then self.onChoose(row.species, row) end
end

function Gen4StarterSelect:update()
  self.spin = self.spin + SPIN_PER_FRAME
  if self.unavailable then return self:close() end
  local input = self.game.input
  if not input then return end
  if not self.pages then self:say(self:currentText()) end

  -- The case opens once, and then stays open.  A player who presses A while it
  -- is still opening skips to the end rather than being made to wait, which is
  -- what the cartridge does with every other unskippable flourish.
  if self.phase == "opening" then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.frame = self.frames - 1
    else
      self.frame = self.frame + FRAME_STEP
    end
    if self.frame >= self.frames - 1 then
      self.frame = self.frames - 1
      self.phase = "intro"
      self:say(self:currentText())
    end
    return
  end

  if self.phase == "intro" then
    if input:wasPressed("a") or input:wasPressed("b") then
      if self.page < #self.pages then
        self.page = self.page + 1
      else
        self.phase = "choosing"
        self:say(self:currentText())
      end
    end
    return
  end

  local n = #self.rows
  if n == 0 then return end
  if input:wasPressed("left") then
    self.index = (self.index - 2) % n + 1
    self.phase = "offering"
    self:say(self:currentText())
  elseif input:wasPressed("right") then
    self.index = self.index % n + 1
    self.phase = "offering"
    self:say(self:currentText())
  elseif input:wasPressed("a") then
    if self.phase == "choosing" then
      self.phase = "offering"
      self:say(self:currentText())
    elseif self.page < #self.pages then
      self.page = self.page + 1
    else
      self:confirm()
    end
  elseif input:wasPressed("b") then
    self.phase = "choosing"
    self:say(self:currentText())
  end
end

-- ------------------------------------------------------------------- draw --

-- The scene, into a canvas of its own with a depth buffer.
--
-- A canvas rather than straight onto the UI surface because a depth test needs
-- a depth buffer attached, and the UI surface has none.  Built once and kept:
-- allocating a pair of canvases every frame is the kind of thing that only
-- shows up as a stutter on somebody else's machine.
function Gen4StarterSelect:drawScene()
  if not self.colour then
    self.colour, self.depth = Gen4Model.newTarget(W, H)
    if not self.colour then self.noDepth = true end
  end
  if self.noDepth then return nil end

  local g = love.graphics
  local previous = { g.getCanvas() }
  g.setCanvas({ self.colour, depthstencil = self.depth })
  g.clear(0, 0, 0, 0, true, true)

  local pose = self:poseNow()
  local centre, distance = self.scene:framing(pose)
  centre = apply(Z_UP_TO_Y_UP, centre)

  local projection = Gen4Model.perspective(math.rad(38), W / H, 1, 4000)
  local view = Gen4Model.orbit(centre, distance * CAMERA_DISTANCE,
                               self.spin, CAMERA_PITCH)
  local viewProjection = multiply(projection, multiply(view, Z_UP_TO_Y_UP))

  if self.ground then self.ground:draw(viewProjection) end
  self.scene:draw(viewProjection, pose)

  g.setCanvas(previous[1] and previous or nil)
  return self.colour
end

function Gen4StarterSelect:draw()
  local g = love.graphics
  g.setColor(0.06, 0.07, 0.12, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)

  local scene = self:drawScene()
  if scene then
    g.draw(scene, 0, 0)
  else
    -- No depth buffer on this device.  The screen still works as a menu; it
    -- simply has no picture, which is better than a briefcase drawn back to
    -- front.
    Font.draw(Strings("CHOOSE A POKéMON"), 24, 40)
  end

  Font.drawDialogueBox(BOX.tx, BOX.ty, BOX.tw, BOX.th)
  local page = self.pages and self.pages[self.page] or ""
  local y = TEXT_Y
  for line in (tostring(page) .. "\n"):gmatch("([^\n]*)\n") do
    if y > (BOX.ty + BOX.th - 1) * 8 then break end
    Font.draw(line, TEXT_X, y)
    y = y + LINE_H
  end

  -- The three names under the case, with the chosen one marked.  The cartridge
  -- puts these on the bottom screen, which this port does not have yet.
  if self.phase ~= "opening" and self.phase ~= "intro" and #self.rows > 0 then
    local slot = math.floor(W / #self.rows)
    for i, row in ipairs(self.rows) do
      local x = (i - 1) * slot + 8
      if i == self.index then
        Font.drawCode(Theme.cursor, x - 8, (BOX.ty - 2) * 8)
      end
      Font.draw(tostring(row.name or ""), x, (BOX.ty - 2) * 8)
    end
  end
  g.setColor(1, 1, 1, 1)
end

return Gen4StarterSelect
