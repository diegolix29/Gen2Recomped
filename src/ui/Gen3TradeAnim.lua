-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE IN-GAME TRADE, AS EMERALD AND FIRERED PLAY IT.
--
-- Reported from play: "Test all in game trades as well ensure the art for
-- trading also properly displayed with rom parity", "Ensure it works for
-- emerald and firered as well".  Special 257 (DoInGameTradeScene) used to
-- swap the two Pokemon and show nothing; src/ui/TradeAnim.lua is the Game
-- Boy cable cinematic and has nothing to do with either cartridge.
--
-- WHAT THIS IS A PORT OF.  pokeemerald src/trade.c and pokefirered
-- src/trade_scene.c: CB2_InitInGameTrade, then CB2_InGameTrade every frame
-- until STATE_WAIT_FADE_OUT_END returns to the field.  CB2_InitInGameTrade
-- zero-allocates the trade state and never sets `isCableTrade`, so
-- DoTradeAnim takes DoTradeAnim_Wireless -- the WIRELESS ADAPTER sequence,
-- signal rings and the white column, even though no adapter is involved.
-- Both cartridges do this, and the two state machines are line-for-line the
-- same apart from where the received Pokemon's cry is played (see
-- STATE_DELAY_FOR_MON_ANIM).  Every state below is that function's own case,
-- in its own order, with its own numbers.
--
-- THE MACHINE UNDER IT.  The scene is not a sequence of pictures; it is BG
-- layers, sprites and palette RAM being driven, and most of what you see is
-- a side effect of that -- the GBA fading in because its palette is faded,
-- the crossing column being a WIN0 over a palette blended to white, the glow
-- being a semi-transparent OBJ alpha-blended over the signal rings by
-- BLDALPHA(16, 4).  So this file carries a small model of exactly the parts
-- the trade code touches:
--
--   * palette RAM, unfaded and faded, with palette.c's own
--     BeginNormalPaletteFade / UpdateNormalPaletteFade (the BG/OBJ halves on
--     alternate frames, deltaY 2 + |delay|, the five-frame finish) and
--     util.c's 5-bit BlendPalette;
--   * the sprite engine's frame and affine animation commands (sprite.c
--     BeginAnim/ContinueAnim/AnimCmd_loop, BeginAffineAnim/ContinueAffineAnim)
--     and the callbacks the trade installs;
--   * the four BG layers the trade enables, scrolled through BGxHOFS/VOFS or,
--     for the zooming GBA, the BgAffineSet matrix, and composited per pixel in
--     a shader with BG priority, WIN0, and BLDALPHA blending;
--   * the four tasks the scene creates (the wireless signal, the two column
--     tasks, the ball fade and the ball's open particles).
--
-- The art -- every BG, sheet and palette -- is the player's own cartridge's,
-- extracted by src/import/Gen3TradeArt.lua as colour-index images.  The
-- Pokemon pictures are the cache's front sprites; their palette blends (the
-- white flash and the ball colour) are applied as the same 5-bit blend in a
-- shader, since a front sprite is stored in colour.

local Music = require("src.core.Music")
local Strings = require("src.core.Strings")
local Sound = require("src.core.Sound")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local bit = require("bit")
local band, bor, rshift, lshift, bxor = bit.band, bit.bor, bit.rshift, bit.lshift, bit.bxor

local Gen3TradeAnim = {}
Gen3TradeAnim.__index = Gen3TradeAnim
Gen3TradeAnim.isOpaque = true

local GBA_W, GBA_H = 240, 160
local RGB_BLACK, RGB_WHITE = 0x0000, 0x7FFF
local PALETTES_ALL = 0xFFFFFFFF

-- C integer division (truncates toward zero) and >> on a signed value
local function idiv(a, b)
  local q = a / b
  return q >= 0 and math.floor(q) or math.ceil(q)
end
local function asr(a, n) return math.floor(a / (2 ^ n)) end

-- ---------------------------------------------------------------------------
-- DoTradeAnim_Wireless's states, by their pokeemerald names and numbers
-- ---------------------------------------------------------------------------
local S = {
  START = 0, MON_SLIDE_IN = 1, SEND_MSG = 10, BYE_BYE = 11,
  POKEBALL_DEPART = 12, POKEBALL_DEPART_WAIT = 13, FADE_OUT_TO_GBA_SEND = 14,
  WAIT_FADE_OUT_TO_GBA_SEND = 20, FADE_IN_TO_GBA_SEND = 21,
  WAIT_FADE_IN_TO_GBA_SEND = 22, GBA_ZOOM_OUT = 23, GBA_FLASH_SEND = 24,
  GBA_STOP_FLASH_SEND = 25, PAN_AWAY_GBA = 26, CREATE_LINK_MON_LEAVING = 27,
  LINK_MON_TRAVEL_OUT = 28, FADE_OUT_TO_CROSSING = 29,
  WAIT_FADE_OUT_TO_CROSSING = 30, FADE_IN_TO_CROSSING = 31,
  WAIT_FADE_IN_TO_CROSSING = 32, CROSSING_LINK_MONS_ENTER = 33,
  CROSSING_BLEND_WHITE_1 = 34, CROSSING_BLEND_WHITE_2 = 35,
  CROSSING_BLEND_WHITE_3 = 36, CROSSING_CREATE_MON_PICS = 37,
  CROSSING_MON_PICS_MOVE = 38, CROSSING_LINK_MONS_EXIT = 39,
  CREATE_LINK_MON_ARRIVING = 40, FADE_OUT_TO_GBA_RECV = 41,
  WAIT_FADE_OUT_TO_GBA_RECV = 42, LINK_MON_TRAVEL_IN = 43, PAN_TO_GBA = 44,
  DESTROY_LINK_MON = 45, LINK_MON_ARRIVED_DELAY = 46,
  MOVE_GBA_TO_CENTER = 47, GBA_FLASH_RECV = 48, UNUSED = 49,
  GBA_STOP_FLASH_RECV = 50, GBA_ZOOM_IN = 51, FADE_OUT_TO_NEW_MON = 52,
  WAIT_FADE_OUT_TO_NEW_MON = 60, FADE_IN_TO_NEW_MON = 61,
  WAIT_FADE_IN_TO_NEW_MON = 62, POKEBALL_ARRIVE = 63,
  FADE_POKEBALL_TO_NORMAL = 64, POKEBALL_ARRIVE_WAIT = 65, SHOW_NEW_MON = 66,
  NEW_MON_MSG = 67, TAKE_CARE_OF_MON = 68, AFTER_NEW_MON_DELAY = 69,
  CHECK_RIBBONS = 70, END_LINK_TRADE = 71, TRY_EVOLUTION = 72,
  FADE_OUT_END = 73, WAIT_FADE_OUT_END = 74,
  GBA_FLASH_SEND_WIRELESS = 124, GBA_STOP_FLASH_SEND_WIRELESS = 125,
  WAIT_WIRELESS_SIGNAL_SEND = 126, PAN_TO_GBA_WIRELESS = 144,
  DESTROY_LINK_MON_WIRELESS = 145, WAIT_WIRELESS_SIGNAL_RECV = 146,
  DELAY_FOR_MON_ANIM = 167, LINK_MON_TRAVEL_OFFSCREEN = 200,
  WAIT_FOR_MON_CRY = 267,
}
Gen3TradeAnim.STATES = S

-- OBJ palette slots, in the order CB2_InitInGameTrade allocates them:
-- LoadTradeMonPic (player 0, partner 1), LoadTradeSequenceSpriteSheetsAnd-
-- Palettes (PALTAG_LINK_MON 2, PALTAG_GBA 3), sPokeBallSpritePalette 4, then
-- the battle ball's (GFX_TAG_POKE_BALL) and the open particles' as they load.
local PAL_MON_PLAYER, PAL_MON_PARTNER, PAL_LINK_MON, PAL_GBA = 0, 1, 2, 3
local PAL_POKEBALL, PAL_BALL, PAL_PARTICLES = 4, 5, 6

-- ---------------------------------------------------------------------------
-- Frame and affine animation tables (src/data/trade.h, pokeball.c,
-- battle_anim_throw.c, data.c).  { f = image, d = duration, h/v = flips },
-- { loop = n }, { jump = target }, { stop = true } -- and affine
-- { x = dx, y = dy, d = duration } (duration 0 = absolute).
-- ---------------------------------------------------------------------------
local function spin(loops)
  local t = {}
  for i = 0, 11 do t[#t + 1] = { f = i * 4, d = 3 } end
  t[#t + 1] = { loop = loops }
  t[#t + 1] = { f = 0, d = 3 }
  t[#t + 1] = { stop = true }
  return t
end
local ANIMS = {
  pokeball = { spin(1), spin(2) },
  glow = { { { f = 0, d = 5, h = true, v = true }, { stop = true } } },
  shadow = { { { f = 0, d = 5, h = true, v = true }, { stop = true } },
             { { f = 8, d = 5, h = true, v = true }, { stop = true } } },
  gbaScreen = function(loops)
    local t = {}
    for _, f in ipairs({ 0, 32, 64, 96, 64, 32, 0 }) do
      t[#t + 1] = { f = f, d = 2, h = true, v = true }
    end
    t[#t + 1] = { loop = loops }
    t[#t + 1] = { stop = true }
    return { t }
  end,
  -- pokeball.c sBallAnimSequences: closed, opening, closing
  ball = { { { f = 0, d = 1 }, { stop = true } },
           { { f = 4, d = 5 }, { f = 8, d = 5 }, { stop = true } },
           { { f = 4, d = 5 }, { f = 0, d = 5 }, { stop = true } } },
  -- sAnim_RegularBall
  particle = { { { f = 0, d = 1 }, { f = 1, d = 1 }, { f = 2, d = 1 },
                 { f = 0, d = 1, h = true }, { f = 2, d = 1 },
                 { f = 1, d = 1 }, { jump = 1 } } },
  mon = { { { f = 0, d = 1 }, { stop = true } } },
}
local AFFINES = {
  pokeball = { { { x = 0, y = 0, d = 1 }, { stop = true } },             -- normal
               { { x = -8, y = 0, d = 20 }, { stop = true } },           -- squish
               { { x = 0x60, y = 0x100, d = 0 }, { x = 0, y = 0, d = 5 },
                 { x = 8, y = 0, d = 20 }, { stop = true } } },          -- unsquish
  glow = { { { x = -10, y = -10, d = 5 }, { x = 10, y = 10, d = 5 },
             { jump = 1 } } },
  -- gAffineAnims_BattleSpriteOpponentSide: NORMAL, EMERGE, RETURN
  mon = { { { x = 0x100, y = 0x100, d = 0 }, { stop = true } },
          { { x = 0x28, y = 0x28, d = 0 }, { x = 0x12, y = 0x12, d = 12 },
            { stop = true } },
          { { x = -2, y = -2, d = 18 }, { x = -0x10, y = -0x10, d = 15 },
            { stop = true } } },
  crossing = { { { x = -0x100, y = 0x100, d = 0 }, { jump = 1 } } },
  -- sAffineAnim_BallRotate_0
  ball = { { { x = 0, y = 0, d = 1 }, { jump = 1 } } },
}

-- the sheets: image key, frame size, and how many tiles one image step is
local SHEETS = {
  pokeball = { key = "obj_pokeball", w = 16, h = 16, tiles = 4 },
  glow = { key = "obj_glow", w = 32, h = 32, tiles = 16 },
  shadow = { key = "obj_shadow", w = 16, h = 32, tiles = 8 },
  gbaScreen = { key = "obj_gbascreen", w = 64, h = 32, tiles = 32 },
  ball = { key = "obj_ball", w = 16, h = 16, tiles = 4 },
  particle = { key = "obj_particles", w = 8, h = 8, tiles = 1 },
}

-- ---------------------------------------------------------------------------
-- shaders
-- ---------------------------------------------------------------------------

-- The BG compositor: BG1 and BG2 sampled out of their index pictures through
-- palette RAM, layered by priority under the OBJ layer (every trade sprite is
-- OBJ priority 0-2, above both), clipped by WIN0 and blended by BLDALPHA.
local COMPOSITE_GLSL = [[
extern Image palTex;
extern Image bg1Tex; extern vec2 bg1Size; extern vec2 bg1Ofs; extern float bg1On;
extern Image bg2Tex; extern vec2 bg2Size; extern vec2 bg2Ofs; extern float bg2On;
extern float bg2Affine; extern vec4 bg2Mat; extern vec2 bg2Ref;
extern float blendOn; extern vec3 tgt1; extern vec3 tgt2; extern vec2 ev;
extern float winOn; extern vec4 win;
const vec2 screen = vec2(240.0, 160.0);

vec3 bgColour(float idx) {
  return Texel(palTex, vec2((idx + 0.5) / 256.0, 0.25)).rgb;
}
float sampleText(Image t, vec2 size, vec2 p) {
  vec2 q = mod(p, size);
  vec4 c = Texel(t, (floor(q) + 0.5) / size);
  return c.a > 0.5 ? floor(c.r * 255.0 + 0.5) : -1.0;
}
vec3 five(vec3 c) { return floor(c * 31.0 + 0.5); }

vec4 effect(vec4 colour, Image objTex, vec2 tc, vec2 sc) {
  vec2 p = floor(tc * screen);
  vec4 obj = Texel(objTex, (p + 0.5) / screen);
  float showBg = 1.0;
  float effects = 1.0;
  if (winOn > 0.5) {
    bool inside = p.x >= win.x && p.x < win.y && p.y >= win.z && p.y < win.w;
    if (!inside) showBg = 0.0;
    effects = 0.0;
  }
  float i1 = -1.0;
  if (bg1On > 0.5 && showBg > 0.5) i1 = sampleText(bg1Tex, bg1Size, p + bg1Ofs);
  float i2 = -1.0;
  if (bg2On > 0.5 && showBg > 0.5) {
    if (bg2Affine > 0.5) {
      vec2 t = floor(bg2Ref + vec2(bg2Mat.x * p.x + bg2Mat.y * p.y,
                                   bg2Mat.z * p.x + bg2Mat.w * p.y));
      if (t.x >= 0.0 && t.y >= 0.0 && t.x < bg2Size.x && t.y < bg2Size.y) {
        vec4 c = Texel(bg2Tex, (t + 0.5) / bg2Size);
        if (c.a > 0.5) i2 = floor(c.r * 255.0 + 0.5);
      }
    } else {
      i2 = sampleText(bg2Tex, bg2Size, p + bg2Ofs);
    }
  }
  // kinds: 0 BG1, 1 BG2, 2 OBJ, 3 backdrop -- top two opaque layers
  float k0 = -1.0; vec3 c0 = vec3(0.0);
  float k1 = -1.0; vec3 c1 = vec3(0.0);
  bool semi = false;
  if (obj.a > 0.01) { k0 = 2.0; c0 = obj.rgb; semi = obj.a < 0.75; }
  if (i1 >= 0.0) {
    if (k0 < 0.0) { k0 = 0.0; c0 = bgColour(i1); }
    else if (k1 < 0.0) { k1 = 0.0; c1 = bgColour(i1); }
  }
  if (i2 >= 0.0) {
    if (k0 < 0.0) { k0 = 1.0; c0 = bgColour(i2); }
    else if (k1 < 0.0) { k1 = 1.0; c1 = bgColour(i2); }
  }
  if (k0 < 0.0) { k0 = 3.0; c0 = bgColour(0.0); }
  else if (k1 < 0.0) { k1 = 3.0; c1 = bgColour(0.0); }
  if (effects > 0.5) {
    float isT1 = (k0 == 0.0) ? tgt1.x : ((k0 == 1.0) ? tgt1.y : ((k0 == 2.0) ? tgt1.z : 0.0));
    float isT2 = (k1 == 0.0) ? tgt2.x : ((k1 == 1.0) ? tgt2.y : ((k1 == 3.0) ? tgt2.z : 0.0));
    if (isT2 > 0.5 && ((blendOn > 0.5 && isT1 > 0.5) || semi)) {
      vec3 a = five(c0), b = five(c1);
      c0 = min(vec3(31.0), floor((a * ev.x + b * ev.y) / 16.0)) / 31.0;
    }
  }
  return vec4(c0, 1.0);
}
]]

-- An index picture through one row of palette RAM.  `bank` is added to a
-- 4bpp sprite's 0..15; a BG picture already carries bank * 16 in its index.
-- `alpha` is what the OBJ layer records: 1 normal, 0.5 semi-transparent.
local INDEX_GLSL = [[
extern Image palTex;
extern float row;
extern float bank;
extern float alpha;
vec4 effect(vec4 colour, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  if (c.a < 0.5) discard;
  float idx = bank * 16.0 + floor(c.r * 255.0 + 0.5);
  vec3 rgb = Texel(palTex, vec2((idx + 0.5) / 256.0, row)).rgb;
  return vec4(rgb, alpha);
}
]]

-- A colour Pokemon picture through its palette slot's BlendPalette state:
-- util.c's c + (((target - c) * coeff) >> 4), on 5-bit channels.
local MON_GLSL = [[
extern vec3 target;
extern float coeff;
vec4 effect(vec4 colour, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  if (c.a < 0.5) discard;
  vec3 a = floor(c.rgb * 31.0 + 0.5);
  vec3 t = floor(target * 31.0 + 0.5);
  vec3 r = a + floor((t - a) * coeff / 16.0);
  return vec4(r / 31.0, 1.0);
}
]]

local shaders
local function getShaders()
  if shaders ~= nil then return shaders or nil end
  local ok, res = pcall(function()
    return {
      composite = love.graphics.newShader(COMPOSITE_GLSL),
      index = love.graphics.newShader(INDEX_GLSL),
      mon = love.graphics.newShader(MON_GLSL),
    }
  end)
  if not ok then
    Logger.warn("gen3 trade: shaders did not compile: %s", tostring(res))
    shaders = false
    return nil
  end
  shaders = res
  return shaders
end

-- ---------------------------------------------------------------------------
-- the record, and whether there is anything to draw with
-- ---------------------------------------------------------------------------
function Gen3TradeAnim.art(game)
  local data = game and game.data
  local art = data and data.gen3_trade_art
  if type(art) ~= "table" or type(art.images) ~= "table"
     or type(art.palettes) ~= "table" then
    return nil
  end
  return art
end

local function loadImage(path)
  if type(path) ~= "string" then return nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  local img
  if okA and Assets and Assets.image then
    local ok, res = pcall(Assets.image, path)
    if ok then img = res end
  end
  if not img and love.graphics and love.graphics.newImage then
    local ok, res = pcall(love.graphics.newImage, path)
    if ok then img = res end
  end
  -- the compositor wraps its own coordinates, so the shared images are left
  -- with whatever wrap mode the rest of the engine set
  if img and img.setFilter then img:setFilter("nearest", "nearest") end
  return img
end

-- ---------------------------------------------------------------------------
-- construction: CB2_InitInGameTrade
-- ---------------------------------------------------------------------------

-- opts: { trade = constants.gen3Trades row, given = the party mon being
-- traded away, received = the mon built by special 256, slot = party index
-- (1-based), onDone = called after STATE_WAIT_FADE_OUT_END }
function Gen3TradeAnim.new(game, opts)
  local self = setmetatable({}, Gen3TradeAnim)
  self.game = game
  self.opts = opts or {}
  self.art = Gen3TradeAnim.art(game)
  self.given = self.opts.given
  self.received = self.opts.received
  self.trade = self.opts.trade or {}
  self.frame = 0
  self.state = S.START
  self.timer = 0
  self.done = false
  -- THE BLACK BEFORE THE SCENE.  The field's fade has five finishing frames
  -- after it reaches black (IsSoftwarePaletteFadeFinishing), Task_InGameTrade
  -- then hands over, and CB2_InitInGameTrade spends states 0 and 5-10 with
  -- DISPCNT cleared -- seven frames of backdrop -- before state 11 turns the
  -- text box and platform on and state 12 starts CB2_InGameTrade.  So twelve
  -- black frames, two of the empty scene, then STATE_START.
  self.initFrames = 14
  self:initHardware()
  self:loadPictures()
  self:initTrade()
  return self
end

function Gen3TradeAnim:uiSize() return GBA_W, GBA_H end

function Gen3TradeAnim:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

-- ---- palette RAM -----------------------------------------------------------

function Gen3TradeAnim:initHardware()
  self.unf, self.fad = {}, {}
  for i = 0, 511 do self.unf[i] = 0; self.fad[i] = 0 end
  -- the Pokemon pictures are stored in colour, so their two OBJ banks keep
  -- a BlendPalette state instead of sixteen words
  self.monBlend = { [PAL_MON_PLAYER] = { coeff = 0, color = 0 },
                    [PAL_MON_PARTNER] = { coeff = 0, color = 0 } }
  self.fade = { active = false, y = 0, targetY = 0, deltaY = 2, delay = 0,
                delayCounter = 0, selected = 0, color = 0, yDec = false,
                objToggle = 0, finishing = false, finishingCounter = 0,
                transferDisabled = false }
  self.paletteDirty = true
  self.reg = {
    mode = 0, bg0 = false, bg1 = false, bg2 = false,
    bg1Src = "gba", bg2Src = "platform",
    blend = { on = false, t1 = { 0, 0, 0 }, t2 = { 0, 0, 0 }, eva = 0, evb = 0 },
    win = { on = false, left = 0, right = 0, top = 0, bottom = 0 },
  }
  self.sprites = {}
  self.tasks = {}
  self.windowText = nil
end

local function words(t, i) return t and t[i + 1] or 0 end

function Gen3TradeAnim:loadPalette(src, offset, count, from)
  from = from or 0
  for i = 0, count - 1 do
    local w = words(src, from + i)
    self.unf[offset + i] = w
    self.fad[offset + i] = w
  end
  -- a Pokemon slot is reset by its own load
  local bank = offset - 256
  if bank >= 0 and bank % 16 == 0 and self.monBlend[bank / 16] then
    self.monBlend[bank / 16] = { coeff = 0, color = 0 }
  end
  self.paletteDirty = true
end

-- util.c BlendPalette: faded = unfaded + (((target - unfaded) * coeff) >> 4)
local function blend555(c, coeff, target)
  local r, g, b = band(c, 31), band(rshift(c, 5), 31), band(rshift(c, 10), 31)
  local tr, tg, tb = band(target, 31), band(rshift(target, 5), 31),
                     band(rshift(target, 10), 31)
  r = r + asr((tr - r) * coeff, 4)
  g = g + asr((tg - g) * coeff, 4)
  b = b + asr((tb - b) * coeff, 4)
  return r + g * 32 + b * 1024
end

function Gen3TradeAnim:blendPalette(offset, count, coeff, color)
  local bank = (offset >= 256) and (offset - 256) / 16 or nil
  if bank and self.monBlend[bank] and count == 16 then
    self.monBlend[bank] = { coeff = coeff, color = band(color, 0x7FFF) }
  else
    for i = offset, offset + count - 1 do
      self.fad[i] = blend555(self.unf[i], coeff, color)
    end
  end
  self.paletteDirty = true
end

function Gen3TradeAnim:blendPalettes(selected, coeff, color)
  local off = 0
  selected = band(selected, 0xFFFFFFFF)
  while selected ~= 0 do
    if band(selected, 1) ~= 0 then self:blendPalette(off, 16, coeff, color) end
    selected = rshift(selected, 1)
    off = off + 16
  end
end

-- palette.c BeginNormalPaletteFade
function Gen3TradeAnim:beginFade(selected, delay, startY, targetY, color)
  local f = self.fade
  if f.active then return false end
  f.deltaY = 2
  if delay < 0 then
    f.deltaY = f.deltaY + (-delay)
    delay = 0
  end
  f.selected = band(selected, 0xFFFFFFFF)
  f.delayCounter = delay
  f.delay = delay
  f.y = startY
  f.targetY = targetY
  f.color = band(color, 0x7FFF)
  f.active = true
  f.yDec = not (startY < targetY)
  self:updateFade()
  return true
end

-- palette.c UpdateNormalPaletteFade, with IsSoftwarePaletteFadeFinishing
function Gen3TradeAnim:updateFade()
  local f = self.fade
  if not f.active then return end
  if f.finishing then
    if f.finishingCounter == 4 then
      f.active = false
      f.finishing = false
      f.finishingCounter = 0
    else
      f.finishingCounter = f.finishingCounter + 1
    end
    return
  end
  if f.objToggle == 0 then
    if f.delayCounter < f.delay then
      f.delayCounter = f.delayCounter + 1
      return
    end
    f.delayCounter = 0
  end
  local selected, off
  if f.objToggle == 0 then
    selected, off = band(f.selected, 0xFFFF), 0
  else
    selected, off = rshift(band(f.selected, 0xFFFFFFFF), 16), 256
  end
  while selected ~= 0 do
    if band(selected, 1) ~= 0 then self:blendPalette(off, 16, f.y, f.color) end
    selected = rshift(selected, 1)
    off = off + 16
  end
  f.objToggle = bxor(f.objToggle, 1)
  if f.objToggle == 0 then
    if f.y == f.targetY then
      f.selected = 0
      f.finishing = true
    elseif not f.yDec then
      f.y = math.min(f.y + f.deltaY, f.targetY)
    else
      f.y = math.max(f.y - f.deltaY, f.targetY)
    end
  end
end

-- ---- BG register helpers (SetGpuReg(REG_OFFSET_DISPCNT, ...)) -------------
function Gen3TradeAnim:dispcnt(mode, bg0, bg1, bg2)
  local r = self.reg
  r.mode, r.bg0, r.bg1, r.bg2 = mode, bg0 or false, bg1 or false, bg2 or false
  -- the whole register is written, so WIN0's enable bit goes with it
  r.win.on = false
end

-- ---- loading ------------------------------------------------------------------
function Gen3TradeAnim:loadPictures()
  local art = self.art
  self.img = {}
  if not art then return end
  for key, path in pairs(art.images) do
    self.img[key] = loadImage(path)
  end
  local Sprites = require("src.pokemon.Sprites")
  local function front(mon)
    if not mon then return nil end
    local path = Sprites.path(self.game.data, mon.species, "front",
                              { mon = mon, kind = "trade" })
    return loadImage(path)
  end
  self.monImg = { [0] = front(self.given), [1] = front(self.received) }
  -- the palette texture: BG row 0, OBJ row 1
  self.palData = love.image.newImageData(256, 2)
  self.palTex = love.graphics.newImage(self.palData)
  self.palTex:setFilter("nearest", "nearest")
  self.canvas = love.graphics.newCanvas(GBA_W, GBA_H)
  self.canvas:setFilter("nearest", "nearest")
  self.objCanvas = love.graphics.newCanvas(GBA_W, GBA_H)
  self.objCanvas:setFilter("nearest", "nearest")
end

local function yOffset(game, species)
  local def = game.data and game.data.pokemon and game.data.pokemon[species]
  local c = def and (def.frontPicCoords or def.picCoords)
  return (c and tonumber(c.yOffset)) or 0
end

local function monName(game, mon)
  if not mon then return "" end
  if mon.nickname and mon.nickname ~= "" then return mon.nickname end
  local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
  return (def and def.name) or tostring(mon.species)
end

function Gen3TradeAnim:initTrade()
  local art = self.art
  if not art then return end
  local P = art.palettes
  -- TradeAnimInit_LoadGfx: the battle text box, bank 0
  self:loadPalette(P.textbox, 0, 16)
  -- sTradeAnim->texX/texY/scrX/scrY/sXY/alpha, CB2_InitInGameTrade state 0
  self.texX, self.texY = 64, 64
  self.scrX, self.scrY = GBA_W / 2, GBA_H / 2
  self.sXY = 256
  self.gbaScale = 0
  self.bg1hofs, self.bg1vofs, self.bg2hofs, self.bg2vofs = 0, 0, 0, 0
  -- LoadTradeMonPic: both pictures at (120, 60), subpriority 6, invisible
  self.monSpecies = { [0] = self.given and self.given.species,
                      [1] = self.received and self.received.species }
  self.mon = {}
  for party = 0, 1 do
    local spr = self:createSprite({ kind = "mon", party = party,
                                    pal = party == 0 and PAL_MON_PLAYER
                                                      or PAL_MON_PARTNER,
                                    priority = 2, affine = "normal",
                                    anims = ANIMS.mon, affines = AFFINES.mon },
                                  120, 60, 6)
    spr.invisible = true
    self.mon[party] = spr
  end
  -- LoadTradeSequenceSpriteSheetsAndPalettes + sPokeBallSpritePalette
  self:loadPalette(P.linkMon, 256 + PAL_LINK_MON * 16, 16)
  self:loadPalette(P.gba, 256 + PAL_GBA * 16, 16)
  self:loadPalette(P.pokeball, 256 + PAL_POKEBALL * 16, 16)
  -- FillWindowPixelBuffer(0, PIXEL_FILL(15)) and SetTradeSequenceBgGpuRegs
  -- (5) then (0)
  self.windowText = ""
  self:setBgRegs(5)
  self:setBgRegs(0)
  -- BufferTradeSceneStrings: STR_VAR_1 the trainer, STR_VAR_3 the trade's
  -- nickname, STR_VAR_2 the nickname of the Pokemon you give
  self.vars = {
    self.trade.otName or (self.received and self.received.ot) or "",
    monName(self.game, self.given),
    self.trade.nickname or monName(self.game, self.received),
  }
end

-- SetTradeSequenceBgGpuRegs
function Gen3TradeAnim:setBgRegs(state)
  local P = self.art.palettes
  local r = self.reg
  if state == 0 then
    self.bg2vofs, self.bg2hofs = 0, 180
    self:dispcnt(0, true, false, true)
    r.bg2Src = "platform"
    self:loadPalette(P.gba2, 16, 48)
  elseif state == 1 then
    self.bg1hofs, self.bg1vofs = 0, 348
    r.bg1Src = "gba"
    self:dispcnt(0, false, true, false)
  elseif state == 2 then
    self.bg1vofs, self.bg1hofs = 0, 0
    self:dispcnt(1, false, true, false)
    r.bg1Src = "closeup"
    self:blendPalettes(0x8, 16, RGB_BLACK)
  elseif state == 3 then
    self:loadPalette(P.signalNone, 48, 16)
    r.bg2Src = "signal"
    self.bg2vofs = 80
    self:dispcnt(0, false, true, true)
  elseif state == 4 then
    self:dispcnt(1, false, false, true)
    self.texX, self.texY = 64, 92
    self.sXY = 32
    self.gbaScale = 1024
  elseif state == 5 then
    self.bg1vofs, self.bg1hofs = 0, 0
  elseif state == 6 then
    self:dispcnt(1, false, false, true)
    self.texX, self.texY = 64, 92
    self.sXY = 256
    self.gbaScale = 128
    self.scrX, self.scrY = 120, 80
  elseif state == 7 then
    self.bg2vofs, self.bg2hofs = 0, 0
    r.blend = { on = false, t1 = { 0, 0, 0 }, t2 = { 0, 0, 0 }, eva = 0, evb = 0 }
    r.bg2Src = "platform"
    self:loadPalette(P.gba2, 16, 48)
  end
end

-- ---------------------------------------------------------------------------
-- the sprite engine (sprite.c)
-- ---------------------------------------------------------------------------

function Gen3TradeAnim:createSprite(t, x, y, subpriority)
  local id = 0
  while self.sprites[id] do id = id + 1 end
  local spr = {
    id = id, x = x, y = y, x2 = 0, y2 = 0, subpriority = subpriority or 0,
    priority = t.priority or 0, kind = t.kind, sheet = t.sheet,
    pal = t.pal or 0, party = t.party, semi = t.semi or false,
    affineMode = t.affine,                -- nil, "normal" or "double"
    anims = t.anims, affines = t.affines,
    animNum = 0, animCmdIndex = 0, animDelayCounter = 0, animLoopCounter = 0,
    animBeginning = true, animEnded = false, image = 0,
    hFlip = false, vFlip = false, flipH = false, flipV = false,
    affineNum = 0, affineCmdIndex = 0, affineDelay = 0, affineLoop = 0,
    affineBeginning = true, affineEnded = false,
    xScale = 256, yScale = 256,
    invisible = false, data = { [0] = 0, 0, 0, 0, 0, 0, 0, 0 },
    callback = t.callback or "dummy",
  }
  self.sprites[id] = spr
  return spr
end

function Gen3TradeAnim:destroySprite(spr)
  if spr and self.sprites[spr.id] == spr then self.sprites[spr.id] = nil end
end

function Gen3TradeAnim.startAnim(spr, n)
  spr.animNum = n
  spr.animBeginning = true
  spr.animEnded = false
end

function Gen3TradeAnim.startAffine(spr, n)
  spr.affineNum = n
  spr.affineCmdIndex, spr.affineDelay, spr.affineLoop = 0, 0, 0
  spr.xScale, spr.yScale = 256, 256
  spr.affineBeginning = true
  spr.affineEnded = false
end

local function setFrame(spr, cmd)
  spr.image = cmd.f
  if not spr.affineMode then
    spr.flipH = (cmd.h or false) ~= spr.hFlip
    spr.flipV = (cmd.v or false) ~= spr.vFlip
  end
end

local continueAnim

local function animFrame(spr, cmd)
  local d = cmd.d
  if d > 0 then d = d - 1 end
  spr.animDelayCounter = d
  setFrame(spr, cmd)
end

-- JumpToTopOfAnimLoop: walk back to just past the previous LOOP command (or
-- to before the first command), so ContinueAnim's ++ lands on the top
local function jumpToTop(spr, cmds)
  if spr.animLoopCounter ~= 0 then
    local i = spr.animCmdIndex - 1
    while i > 0 and not cmds[i - 1 + 1].loop do i = i - 1 end
    spr.animCmdIndex = i - 1
  end
end

continueAnim = function(spr)
  local cmds = spr.anims[spr.animNum + 1]
  if spr.animDelayCounter > 0 then
    spr.animDelayCounter = spr.animDelayCounter - 1
    local cmd = cmds[spr.animCmdIndex + 1]
    if cmd and cmd.f and not spr.affineMode then
      spr.flipH = (cmd.h or false) ~= spr.hFlip
      spr.flipV = (cmd.v or false) ~= spr.vFlip
    end
    return
  end
  spr.animCmdIndex = spr.animCmdIndex + 1
  local cmd = cmds[spr.animCmdIndex + 1]
  if not cmd or cmd.stop then
    spr.animCmdIndex = spr.animCmdIndex - 1
    spr.animEnded = true
  elseif cmd.jump then
    spr.animCmdIndex = cmd.jump - 1
    animFrame(spr, cmds[spr.animCmdIndex + 1])
  elseif cmd.loop then
    if spr.animLoopCounter ~= 0 then
      spr.animLoopCounter = spr.animLoopCounter - 1
    else
      spr.animLoopCounter = cmd.loop
    end
    jumpToTop(spr, cmds)
    continueAnim(spr)
  else
    animFrame(spr, cmd)
  end
end

local function beginAnim(spr)
  local cmds = spr.anims[spr.animNum + 1]
  spr.animCmdIndex = 0
  spr.animEnded = false
  spr.animLoopCounter = 0
  local cmd = cmds[1]
  if cmd and cmd.f then
    spr.animBeginning = false
    animFrame(spr, cmd)
  end
end

-- ApplyAffineAnimFrame: a duration means relative (and one step is spent
-- now), none means absolute
local function applyAffine(spr, cmd)
  if cmd.d > 0 then
    spr.xScale = spr.xScale + cmd.x
    spr.yScale = spr.yScale + cmd.y
    spr.affineDelay = cmd.d - 1
  else
    spr.xScale, spr.yScale = cmd.x, cmd.y
    spr.affineDelay = 0
  end
end

local function continueAffine(spr)
  local cmds = spr.affines[spr.affineNum + 1]
  if spr.affineDelay > 0 then
    spr.affineDelay = spr.affineDelay - 1
    local cmd = cmds[spr.affineCmdIndex + 1]
    spr.xScale = spr.xScale + cmd.x
    spr.yScale = spr.yScale + cmd.y
    return
  end
  spr.affineCmdIndex = spr.affineCmdIndex + 1
  local cmd = cmds[spr.affineCmdIndex + 1]
  if not cmd or cmd.stop then
    spr.affineEnded = true
    spr.affineCmdIndex = spr.affineCmdIndex - 1
  elseif cmd.jump then
    spr.affineCmdIndex = cmd.jump - 1
    applyAffine(spr, cmds[spr.affineCmdIndex + 1])
  else
    applyAffine(spr, cmd)
  end
end

local function beginAffine(spr)
  local cmds = spr.affines and spr.affines[spr.affineNum + 1]
  if not (spr.affineMode and cmds) then return end
  spr.affineCmdIndex, spr.affineDelay, spr.affineLoop = 0, 0, 0
  spr.affineBeginning = false
  spr.affineEnded = false
  applyAffine(spr, cmds[1])
end

function Gen3TradeAnim.animateSprite(spr)
  if spr.anims then
    if spr.animBeginning then beginAnim(spr) else continueAnim(spr) end
  end
  if spr.affineMode and spr.affines then
    if spr.affineBeginning then beginAffine(spr) else continueAffine(spr) end
  end
end

-- ---------------------------------------------------------------------------
-- sounds
-- ---------------------------------------------------------------------------
function Gen3TradeAnim:se(name)
  local n = self.art and self.art.sounds and self.art.sounds[name]
  local data = self.game.data
  if not data then return end
  local ok = pcall(function()
    local src = Sound.playNamedEffect and Sound.playNamedEffect(data, name)
    if not src and n then Sound.playId(data, n) end
  end)
  local _ = ok
end

function Gen3TradeAnim:cry(species)
  if not species then return end
  local ok, src = pcall(Sound.playCry, self.game.data, species)
  self.crySource = ok and src or nil
end

function Gen3TradeAnim:isCryFinished()
  local src = self.crySource
  if not src then return true end
  local ok, playing = pcall(src.isPlaying, src)
  return not (ok and playing)
end

-- ---------------------------------------------------------------------------
-- sprite callbacks
-- ---------------------------------------------------------------------------
local CB = {}

CB.dummy = function() end

-- trade.c SpriteCB_LinkMonGlowWireless
CB.glowWireless = function(self, spr)
  if not spr.invisible then
    spr.data[0] = spr.data[0] + 1
    if spr.data[0] == 10 then
      self:se("M_SWAGGER2")
      spr.data[0] = 0
    end
  end
end

-- SpriteCB_LinkMonShadow: colour 4 of the link mon palette walks the
-- twelve-step cycle while data[1] is clear
CB.shadow = function(self, spr)
  if spr.data[1] == 0 then
    spr.data[0] = spr.data[0] + 1
    if spr.data[0] == 12 then spr.data[0] = 0 end
    self:loadPalette(self.art.palettes.linkMonShadow,
                     256 + spr.pal * 16 + 4, 1, spr.data[0])
  end
end

-- SpriteCB_GbaScreen
CB.gbaScreen = function(self, spr)
  spr.data[0] = spr.data[0] + 1
  if spr.data[0] == 15 then
    self:se("M_MINIMIZE")
    spr.data[0] = 0
  end
end

-- SpriteCB_BouncingPokeballDepart / DepartEnd
CB.pokeballDepart = function(self, spr)
  local vel = self.art.velocity
  spr.y2 = spr.y2 + (vel[spr.data[0] + 1] or 0)
  if spr.data[0] == 22 then self:se("BALL_BOUNCE_1") end
  spr.data[0] = spr.data[0] + 1
  if spr.data[0] == 44 then
    self:se("M_MEGA_KICK")
    spr.callback = "pokeballDepartEnd"
    spr.data[0] = 0
    self:beginFade(lshift(1, 16 + spr.pal), -1, 0, 16, RGB_WHITE)
  end
end

CB.pokeballDepartEnd = function(self, spr)
  local vel = self.art.velocity
  if spr.data[1] == 20 then Gen3TradeAnim.startAffine(spr, 1) end
  spr.data[1] = spr.data[1] + 1
  if spr.data[1] > 20 then
    spr.y2 = spr.y2 - (vel[spr.data[0] + 1] or 0)
    spr.data[0] = spr.data[0] + 1
    if spr.data[0] == 23 then
      self:destroySprite(spr)
      self.state = S.FADE_OUT_TO_GBA_SEND
    end
  end
end

-- SpriteCB_BouncingPokeballArrive
CB.pokeballArrive = function(self, spr)
  local vel = self.art.velocity
  if spr.data[2] == 0 then
    spr.y = spr.y + 4
    if spr.y > spr.data[3] then
      spr.data[2] = spr.data[2] + 1
      spr.data[0] = 22
      self:se("BALL_BOUNCE_1")
    end
  else
    if spr.data[0] == 66 then self:se("BALL_BOUNCE_2") end
    if spr.data[0] == 92 then self:se("BALL_BOUNCE_3") end
    if spr.data[0] == 107 then self:se("BALL_BOUNCE_4") end
    spr.y2 = spr.y2 + (vel[spr.data[0] + 1] or 0)
    spr.data[0] = spr.data[0] + 1
    if spr.data[0] == 108 then spr.callback = "dummy" end
  end
end

-- pokeball.c SpriteCB_TradePokeball / SendOff / End.  sDelay = data[1],
-- sMonSpriteId = data[0], sMonPalNum = data[2], sTimer = data[5]
CB.tradePokeball = function(self, spr)
  if spr.data[1] == 0 then
    local mon = self.sprites[spr.data[0]]
    Gen3TradeAnim.startAnim(spr, 1)
    self:openParticles(spr.x, spr.y - 5, spr.priority,
                       spr.subpriority ~= 0 and spr.subpriority - 1 or 0)
    self:ballFadeMon(spr.data[2], spr.fadePalettes)
    spr.callback = "tradePokeballSendOff"
    if mon then
      Gen3TradeAnim.startAffine(mon, 2)        -- BATTLER_AFFINE_RETURN
      Gen3TradeAnim.animateSprite(mon)
      mon.data[1] = 0
    end
  else
    spr.data[1] = spr.data[1] - 1
  end
end

CB.tradePokeballSendOff = function(self, spr)
  spr.data[5] = spr.data[5] + 1
  if spr.data[5] == 11 then self:se("BALL_TRADE") end
  local mon = self.sprites[spr.data[0]]
  if not mon or mon.affineEnded then
    Gen3TradeAnim.startAnim(spr, 2)
    if mon then mon.invisible = true end
    spr.data[5] = 0
    spr.callback = "tradePokeballEnd"
  else
    mon.data[1] = mon.data[1] + 96
    mon.y2 = asr(-mon.data[1], 8)
  end
end

CB.tradePokeballEnd = function(self, spr)
  if spr.animEnded then spr.callback = "dummy" end
end

-- pokeball.c SpriteCB_PokeballReleaseMon / SpriteCB_ReleasedMonFlyOut.
-- data[0] mon, data[1] delay, data[2] pal, data[5]/[6] final x/y, data[7]
-- the sine index
CB.releaseMon = function(self, spr)
  if spr.data[1] == 0 then
    local mon = self.sprites[spr.data[0]]
    Gen3TradeAnim.startAnim(spr, 1)
    self:openParticles(spr.x, spr.y - 5, spr.priority,
                       spr.subpriority ~= 0 and spr.subpriority - 1 or 0)
    self:ballFadeMon(spr.data[2], spr.fadePalettes)
    spr.callback = "releasedMonFlyOut"
    if mon then
      mon.invisible = false
      Gen3TradeAnim.startAffine(mon, 1)        -- BATTLER_AFFINE_EMERGE
      Gen3TradeAnim.animateSprite(mon)
      mon.data[1] = 0x1000
    end
    spr.data[7] = 0
  else
    spr.data[1] = spr.data[1] - 1
  end
end

CB.releasedMonFlyOut = function(self, spr)
  local emerged, arrived = false, false
  local mon = self.sprites[spr.data[0]]
  if spr.animEnded then spr.invisible = true end
  if not mon then return end
  if mon.affineEnded then
    Gen3TradeAnim.startAffine(mon, 0)          -- BATTLER_AFFINE_NORMAL
    emerged = true
  end
  mon.x = idiv((spr.data[5] - spr.x) * spr.data[7], 128) + spr.x
  mon.y = idiv((spr.data[6] - spr.y) * spr.data[7], 128) + spr.y
  if spr.data[7] < 128 then
    local sine = -idiv(self.art.sine[band(spr.data[7], 0xFF) + 1] or 0, 8)
    spr.data[7] = spr.data[7] + 4
    mon.x2, mon.y2 = sine, sine
  else
    mon.x, mon.y = spr.data[5], spr.data[6]
    mon.x2, mon.y2 = 0, 0
    arrived = true
  end
  if spr.animEnded and emerged and arrived then
    -- Emerald: DoMonFrontSpriteAnimation -- the cry and the species' own
    -- front animation.  FireRed's release has neither.
    if self.art.releaseAnimates then
      self:cry(mon.species)
      local okA, MonAnim = pcall(require, "src.pokemon.MonAnim")
      if okA and MonAnim then
        local anim = MonAnim.new(self.game.data, mon.species)
        if anim then anim:restart(); mon.monAnim = anim end
      end
    end
    self:destroySprite(spr)
  end
end

-- battle_anim_throw.c PokeBallOpenParticleAnimation_Step1/2
CB.particleWait = function(self, spr)
  if spr.data[1] == 0 then
    spr.callback = "particleMove"
  else
    spr.data[1] = spr.data[1] - 1
  end
end

CB.particleMove = function(self, spr)
  local sine = self.art.sine
  local a = band(spr.data[0], 0xFF)
  spr.x2 = asr((sine[a + 1] or 0) * spr.data[1], 8)
  spr.y2 = asr((sine[band(a + 64, 0xFF) + 1] or 0) * spr.data[1], 8)
  spr.data[1] = spr.data[1] + 2
  if spr.data[1] == 50 then self:destroySprite(spr) end
end

-- ---------------------------------------------------------------------------
-- the tasks
-- ---------------------------------------------------------------------------
-- CreateTask only links the task in; it first runs in this frame's RunTasks,
-- which comes after DoTradeAnim in CB2_InGameTrade
function Gen3TradeAnim:createTask(name, fields)
  local task = fields or {}
  task.name = name
  task.data = task.data or { [0] = 0, 0, 0, 0, 0, 0, 0, 0 }
  self.tasks[#self.tasks + 1] = task
  return task
end

function Gen3TradeAnim:taskActive(name)
  for _, t in ipairs(self.tasks) do
    if t.name == name and not t.dead then return true end
  end
  return false
end

-- AnimateBallOpenParticles(x, y, priority, subpriority, BALL_POKE): the
-- sheet and palette load, SE_BALL_OPEN, and one particle a frame for sixteen
-- frames out of the task
function Gen3TradeAnim:openParticles(x, y, priority, subpriority)
  self:loadPalette(self.art.palettes.particles, 256 + PAL_PARTICLES * 16, 16)
  self:se("BALL_OPEN")
  self.tasks[#self.tasks + 1] = {
    name = "particleTask", x = x, y = y, priority = priority,
    subpriority = subpriority, data = { [0] = 0 },
  }
end

function Gen3TradeAnim:particleTask(task)
  if task.data[0] < 16 then
    local spr = self:createSprite({ kind = "particle", sheet = "particle",
                                    pal = PAL_PARTICLES, anims = ANIMS.particle,
                                    callback = "particleWait" },
                                  task.x, task.y, task.subpriority)
    spr.priority = task.priority
    local a = task.data[0]
    if a >= 8 then a = a - 8 end
    spr.data[0] = a * 32
    if task.data[0] == 15 then
      task.dead = true
      return
    end
  end
  task.data[0] = task.data[0] + 1
end

-- battle_anim_throw.c LaunchBallFadeMonTask(TRUE, pal, selected, BALL_POKE):
-- the Pokemon's palette at the ball's colour at once, the selected palettes
-- to white and back, then the Pokemon's palette walked home over 17 frames
function Gen3TradeAnim:ballFadeMon(monPal, selected)
  local color = self.art.ballFadeColor or 0x7ADF
  self:blendPalette(256 + monPal * 16, 16, 16, color)
  self.tasks[#self.tasks + 1] = {
    name = "fadeMonToNormal", pal = monPal, selected = selected,
    color = color, coeff = 16, dcoeff = -1, timer = 0,
  }
  self:beginFade(selected, 0, 0, 16, RGB_WHITE)
end

function Gen3TradeAnim:fadeMonToNormal(task)
  if task.step then
    if task.timer <= 16 then
      self:blendPalette(256 + task.pal * 16, 16, task.coeff, task.color)
      task.coeff = task.coeff + task.dcoeff
      task.timer = task.timer + 1
    else
      task.dead = true
    end
  elseif not self.fade.active then
    self:beginFade(task.selected, 0, 16, 0, RGB_WHITE)
    task.step = true
  end
end

-- trade.c Task_AnimateWirelessSignal (tIdx data[0], tCounter data[1],
-- tSignalComingBack data[2])
function Gen3TradeAnim:wirelessSignal(task)
  local params = self.art.signalParams
  local row = params[task.data[0] + 1] or { 16, 0xFF }
  local palIdx = row[1] * 16
  local P = self.art.palettes
  if palIdx == 256 then
    self:loadPalette(P.signalNone, 48, 16)
  elseif task.data[2] == 0 then
    self:loadPalette(P.signalSend, 48, 16, palIdx)
  else
    self:loadPalette(P.signalRecv, 48, 16, palIdx)
  end
  if row[1] == 0 and task.data[1] == 0 then self:se("M_HEAL_BELL") end
  if task.data[1] == row[2] then
    task.data[0] = task.data[0] + 1
    task.data[1] = 0
    local nextRow = params[task.data[0] + 1]
    if not nextRow or nextRow[2] == 0xFF then task.dead = true end
  else
    task.data[1] = task.data[1] + 1
  end
end

-- Task_OpenCenterWhiteColumn / Task_CloseCenterWhiteColumn: WIN0 over the
-- middle of the screen, BG0/BG1/OBJ inside and only OBJ outside
function Gen3TradeAnim:openColumn(task)
  local w = self.reg.win
  if task.data[0] == 0 then
    self.winLeft, self.winRight = GBA_W / 2, GBA_W / 2
    self.winTop, self.winBottom = 0, GBA_H
    w.on = true
  end
  w.left, w.right, w.top, w.bottom = self.winLeft, self.winRight,
                                     self.winTop, self.winBottom
  task.data[0] = task.data[0] + 1
  self.winLeft = self.winLeft - 5
  self.winRight = self.winRight + 5
  if self.winLeft < 80 then task.dead = true end
end

function Gen3TradeAnim:closeColumn(task)
  local w = self.reg.win
  if task.data[0] == 0 then
    self.winLeft, self.winRight = 80, GBA_W - 80
  end
  w.left, w.right, w.top, w.bottom = self.winLeft, self.winRight,
                                     self.winTop, self.winBottom
  if self.winLeft ~= GBA_W / 2 then
    task.data[0] = task.data[0] + 1
    self.winLeft = self.winLeft + 5
    self.winRight = self.winRight - 5
    if self.winLeft > GBA_W / 2 - 5 then
      self:blendPalettes(0x8, 0, RGB_WHITE)
    end
  else
    w.on = false
    task.dead = true
  end
end

function Gen3TradeAnim:runTasks()
  local list = self.tasks
  local i = 1
  -- a task created while the list runs starts on the next frame, as
  -- CreateTask's does when its priority sorts it after the running one
  local n = #list
  while i <= n do
    local t = list[i]
    if not t.dead and self[t.name] then self[t.name](self, t) end
    i = i + 1
  end
  local keep = {}
  for _, t in ipairs(list) do if not t.dead then keep[#keep + 1] = t end end
  self.tasks = keep
end

-- ---------------------------------------------------------------------------
-- text
-- ---------------------------------------------------------------------------
local FALLBACK_TEXT = {
  sending = Strings.source("{VAR2} will be\nsent to {VAR1}."),
  goodbye = "Bye-bye, {VAR2}!",
  arrived = "{VAR1} sent over {VAR3}.",
  takeCare = "Take good care of {VAR3}!",
}

function Gen3TradeAnim:say(role)
  local text = (self.art.text or {})[role] or Strings(FALLBACK_TEXT[role] or "")
  local vars = self.vars
  -- a function replacement is used verbatim, so a nickname with a percent
  -- sign needs no escaping here
  text = text:gsub("{VAR(%d)}", function(n)
    return tostring(vars[tonumber(n)] or "")
  end)
  self.windowText = text
end

-- ---------------------------------------------------------------------------
-- DoTradeAnim_Wireless
-- ---------------------------------------------------------------------------
function Gen3TradeAnim:stateMachine()
  local st = self.state
  local mon = self.mon
  local fade = self.fade

  if st == S.START then
    mon[0].invisible = false
    mon[0].x2 = -180
    mon[0].y2 = yOffset(self.game, self.monSpecies[0])
    self.state = st + 1
    -- cachedMapMusic is the field's; Music.restoreMap brings it back at the
    -- end (STATE_WAIT_FADE_OUT_END's PlayNewMapMusic)
    pcall(Music.play, self.game.data, Music.special(self.game.data, "evolution"))
  elseif st == S.MON_SLIDE_IN then
    if self.bg2hofs > 0 then
      mon[0].x2 = mon[0].x2 + 3
      self.bg2hofs = self.bg2hofs - 3
    else
      mon[0].x2 = 0
      self.bg2hofs = 0
      self.state = S.SEND_MSG
    end
  elseif st == S.SEND_MSG then
    self:say("sending")
    if not (self.given and (self.given.isEgg or self.given.egg)) then
      self:cry(self.monSpecies[0])
    end
    self.state = S.BYE_BYE
    self.timer = 0
  elseif st == S.BYE_BYE then
    self.timer = self.timer + 1
    if self.timer == 80 then
      -- CreateTradePokeballSprite(mon, pal, 120, 32, 2, 1, 0x14, 0xfffff)
      self:loadPalette(self.art.palettes.ball, 256 + PAL_BALL * 16, 16)
      local ball = self:createSprite({ kind = "ball", sheet = "ball",
                                       pal = PAL_BALL, priority = 2,
                                       affine = "double", anims = ANIMS.ball,
                                       affines = AFFINES.ball,
                                       callback = "tradePokeball" },
                                     120, 32, 1)
      ball.data[0] = mon[0].id
      ball.data[1] = 0x14
      ball.data[2] = PAL_MON_PLAYER
      ball.fadePalettes = 0xFFFFF
      self.releaseBall = ball
      self.state = st + 1
      self:say("goodbye")
    end
  elseif st == S.POKEBALL_DEPART then
    local rb = self.releaseBall
    if rb and rb.callback == "dummy" then
      local pb = self:createSprite({ kind = "pokeball", sheet = "pokeball",
                                     pal = PAL_POKEBALL, priority = 0,
                                     affine = "normal",
                                     anims = ANIMS.pokeball,
                                     affines = AFFINES.pokeball,
                                     callback = "pokeballDepart" },
                                   120, 32, 0)
      self.bouncingBall = pb
      self:destroySprite(rb)
      self.state = st + 1
    end
  elseif st == S.POKEBALL_DEPART_WAIT then
    -- the sprite's own callback moves the state on
  elseif st == S.FADE_OUT_TO_GBA_SEND then
    self:beginFade(PALETTES_ALL, 0, 0, 16, RGB_BLACK)
    self.state = S.WAIT_FADE_OUT_TO_GBA_SEND
  elseif st == S.WAIT_FADE_OUT_TO_GBA_SEND then
    if not fade.active then
      self:setBgRegs(4)
      self.windowText = ""
      self.state = st + 1
    end
  elseif st == S.FADE_IN_TO_GBA_SEND then
    self:beginFade(PALETTES_ALL, -1, 16, 0, RGB_BLACK)
    self.state = st + 1
  elseif st == S.WAIT_FADE_IN_TO_GBA_SEND then
    if not fade.active then self.state = S.GBA_ZOOM_OUT end
  elseif st == S.GBA_ZOOM_OUT then
    if self.gbaScale > 0x100 then
      self.gbaScale = self.gbaScale - 0x34
    else
      self:setBgRegs(1)
      self.gbaScale = 0x80
      self.state = S.GBA_FLASH_SEND_WIRELESS
      self.timer = 0
    end
    self.sXY = math.floor(0x8000 / self.gbaScale)
  elseif st == S.GBA_FLASH_SEND_WIRELESS then
    self.timer = self.timer + 1
    if self.timer > 20 then
      self:setBgRegs(3)
      self.flash = self:createSprite({ kind = "gbaScreen", sheet = "gbaScreen",
                                       pal = PAL_GBA, priority = 1,
                                       anims = ANIMS.gbaScreen(2),
                                       callback = "gbaScreen" }, 120, 80, 0)
      self.state = st + 1
    end
  elseif st == S.GBA_STOP_FLASH_SEND_WIRELESS then
    if self.flash and self.flash.animEnded then
      self:destroySprite(self.flash)
      -- BLDCNT_TGT1_BG1 | BLDCNT_TGT1_OBJ | BLDCNT_EFFECT_BLEND |
      -- BLDCNT_TGT2_BG2, BLDALPHA_BLEND(16, 4)
      self.reg.blend = { on = true, t1 = { 1, 0, 1 }, t2 = { 0, 1, 0 },
                         eva = 16, evb = 4 }
      self:createTask("wirelessSignal")
      self.state = st + 1
    end
  elseif st == S.WAIT_WIRELESS_SIGNAL_SEND then
    if not self:taskActive("wirelessSignal") then
      self.state = S.PAN_AWAY_GBA
    end
  elseif st == S.PAN_AWAY_GBA then
    self.bg1vofs = self.bg1vofs - 1
    if self.bg1vofs == 316 then self.state = st + 1 end
  elseif st == S.CREATE_LINK_MON_LEAVING then
    self.glow = self:createSprite({ kind = "glow", sheet = "glow",
                                    pal = PAL_LINK_MON, priority = 1,
                                    semi = true, affine = "normal",
                                    anims = ANIMS.glow, affines = AFFINES.glow,
                                    callback = "glowWireless" }, 120, 80, 3)
    self.shadow = self:createSprite({ kind = "shadow", sheet = "shadow",
                                      pal = PAL_LINK_MON, priority = 1,
                                      anims = ANIMS.shadow,
                                      callback = "shadow" }, 120, 80, 0)
    Gen3TradeAnim.startAnim(self.shadow, 1)    -- ANIM_LINKMON_SMALL
    self.state = st + 1
  elseif st == S.LINK_MON_TRAVEL_OUT then
    self.bg1vofs = self.bg1vofs - 3
    if self.bg1vofs == 166 then self.state = S.LINK_MON_TRAVEL_OFFSCREEN end
    self:dispcnt(1, false, true, false)
  elseif st == S.LINK_MON_TRAVEL_OFFSCREEN then
    self.glow.y = self.glow.y - 2
    self.shadow.y = self.shadow.y - 2
    if self.glow.y < -8 then self.state = S.FADE_OUT_TO_CROSSING end
  elseif st == S.FADE_OUT_TO_CROSSING then
    self:beginFade(PALETTES_ALL, -1, 0, 16, RGB_BLACK)
    self.state = S.WAIT_FADE_OUT_TO_CROSSING
  elseif st == S.WAIT_FADE_OUT_TO_CROSSING then
    if not fade.active then
      self:destroySprite(self.glow)
      self:destroySprite(self.shadow)
      self:setBgRegs(2)
      self.state = st + 1
    end
  elseif st == S.FADE_IN_TO_CROSSING then
    self:beginFade(PALETTES_ALL, -1, 16, 0, RGB_BLACK)
    self.cross1 = self:createSprite({ kind = "shadow", sheet = "shadow",
                                      pal = PAL_LINK_MON, priority = 1,
                                      anims = ANIMS.shadow,
                                      callback = "shadow" }, 111, 170, 0)
    self.cross2 = self:createSprite({ kind = "shadow", sheet = "shadow",
                                      pal = PAL_LINK_MON, priority = 1,
                                      anims = ANIMS.shadow,
                                      callback = "shadow" }, 129, -10, 0)
    self.state = st + 1
  elseif st == S.WAIT_FADE_IN_TO_CROSSING then
    if not fade.active then
      self:se("WARP_OUT")
      self.state = st + 1
    end
    self.cross1.y2 = self.cross1.y2 - 3
    self.cross2.y2 = self.cross2.y2 + 3
  elseif st == S.CROSSING_LINK_MONS_ENTER then
    self.cross1.y2 = self.cross1.y2 - 3
    self.cross2.y2 = self.cross2.y2 + 3
    if self.cross1.y2 <= -90 then
      self.cross1.data[1] = 1
      self.cross2.data[1] = 1
      self.state = st + 1
      self:createTask("openColumn")
    end
  elseif st == S.CROSSING_BLEND_WHITE_1 or st == S.CROSSING_BLEND_WHITE_2
      or st == S.CROSSING_BLEND_WHITE_3 then
    self:blendPalettes(0x8, 16, RGB_WHITE)
    self.state = st + 1
  elseif st == S.CROSSING_CREATE_MON_PICS then
    local m0, m1 = mon[0], mon[1]
    local noFlip = self.art.noFlip or {}
    if not noFlip[self.monSpecies[0]] then
      m0.affines = AFFINES.crossing
      m0.affineMode = "double"
    end
    Gen3TradeAnim.startAffine(m0, 0)
    Gen3TradeAnim.startAffine(m1, 0)
    m0.x, m1.x = 40, 200
    m0.y, m1.y = 192, -32
    m0.invisible, m1.invisible = false, false
    self.state = st + 1
  elseif st == S.CROSSING_MON_PICS_MOVE then
    mon[0].y2 = mon[0].y2 - 3
    mon[1].y2 = mon[1].y2 + 3
    if mon[0].y2 < -GBA_H and mon[0].y2 >= -GBA_H - 3 then
      self:se("WARP_IN")
    end
    if mon[0].y2 < -222 then
      self.cross1.data[1] = 0
      self.cross2.data[1] = 0
      self.state = st + 1
      mon[0].invisible = true
      mon[1].invisible = true
      self:createTask("closeColumn")
    end
  elseif st == S.CROSSING_LINK_MONS_EXIT then
    self.cross1.y2 = self.cross1.y2 - 3
    self.cross2.y2 = self.cross2.y2 + 3
    if self.cross1.y2 <= -222 then
      self:beginFade(PALETTES_ALL, -1, 0, 16, RGB_BLACK)
      self.state = st + 1
      self:destroySprite(self.cross1)
      self:destroySprite(self.cross2)
    end
  elseif st == S.CREATE_LINK_MON_ARRIVING then
    if not fade.active then
      self.state = st + 1
      self:setBgRegs(1)
      self.bg1vofs = 166
      self:setBgRegs(3)
      self.bg2vofs = 412
      self.glow = self:createSprite({ kind = "glow", sheet = "glow",
                                      pal = PAL_LINK_MON, priority = 1,
                                      semi = true, affine = "normal",
                                      anims = ANIMS.glow,
                                      affines = AFFINES.glow,
                                      callback = "glowWireless" },
                                    120, -20, 3)
      self.shadow = self:createSprite({ kind = "shadow", sheet = "shadow",
                                        pal = PAL_LINK_MON, priority = 1,
                                        anims = ANIMS.shadow,
                                        callback = "shadow" }, 120, -20, 0)
      Gen3TradeAnim.startAnim(self.shadow, 1)
    end
  elseif st == S.FADE_OUT_TO_GBA_RECV then
    self:beginFade(PALETTES_ALL, -1, 16, 0, RGB_BLACK)
    self.state = st + 1
  elseif st == S.WAIT_FADE_OUT_TO_GBA_RECV then
    self:dispcnt(0, false, true, false)
    if not fade.active then self.state = st + 1 end
  elseif st == S.LINK_MON_TRAVEL_IN then
    self.glow.y2 = self.glow.y2 + 4
    self.shadow.y2 = self.shadow.y2 + 4
    if self.glow.y2 + self.glow.y == 64 then
      self.state = S.PAN_TO_GBA_WIRELESS
      self.timer = 0
    end
  elseif st == S.PAN_TO_GBA_WIRELESS then
    self:dispcnt(0, false, true, true)
    self.bg1vofs = self.bg1vofs + 3
    self.bg2vofs = self.bg2vofs + 3
    self.timer = self.timer + 1
    if self.timer == 10 then
      -- gTasks[taskId].tSignalComingBack = TRUE
      self:createTask("wirelessSignal",
                      { data = { [0] = 0, 0, 1, 0, 0, 0, 0, 0 } })
    end
    if self.bg1vofs > 316 then
      self.bg1vofs = 316
      self.state = st + 1
    end
  elseif st == S.DESTROY_LINK_MON_WIRELESS then
    self:destroySprite(self.glow)
    self:destroySprite(self.shadow)
    self.state = st + 1
    self.timer = 0
  elseif st == S.WAIT_WIRELESS_SIGNAL_RECV then
    if not self:taskActive("wirelessSignal") then
      self.state = S.LINK_MON_ARRIVED_DELAY
      self.timer = 0
    end
  elseif st == S.LINK_MON_ARRIVED_DELAY then
    self.timer = self.timer + 1
    if self.timer == 10 then self.state = st + 1 end
  elseif st == S.MOVE_GBA_TO_CENTER then
    self.bg1vofs = self.bg1vofs + 1
    if self.bg1vofs > 348 then
      self.bg1vofs = 348
      self.state = st + 1
    end
  elseif st == S.GBA_FLASH_RECV then
    self.flash = self:createSprite({ kind = "gbaScreen", sheet = "gbaScreen",
                                     pal = PAL_GBA, priority = 1,
                                     anims = ANIMS.gbaScreen(8),
                                     callback = "gbaScreen" }, 120, 80, 0)
    self.state = S.GBA_STOP_FLASH_RECV
  elseif st == S.GBA_STOP_FLASH_RECV then
    if self.flash and self.flash.animEnded then
      self:destroySprite(self.flash)
      self:setBgRegs(6)
      self.state = st + 1
      self:se("M_SAND_ATTACK")
    end
  elseif st == S.GBA_ZOOM_IN then
    if self.gbaScale < 0x400 then
      self.gbaScale = self.gbaScale + 0x34
    else
      self.gbaScale = 0x400
      self.state = st + 1
    end
    self.sXY = math.floor(0x8000 / self.gbaScale)
  elseif st == S.FADE_OUT_TO_NEW_MON then
    self:beginFade(PALETTES_ALL, 0, 0, 16, RGB_BLACK)
    self.state = S.WAIT_FADE_OUT_TO_NEW_MON
  elseif st == S.WAIT_FADE_OUT_TO_NEW_MON then
    if not fade.active then
      self:setBgRegs(5)
      self:setBgRegs(7)
      fade.transferDisabled = true
      self.state = st + 1
    end
  elseif st == S.FADE_IN_TO_NEW_MON then
    fade.transferDisabled = false
    self.paletteDirty = true
    self:beginFade(PALETTES_ALL, 0, 16, 0, RGB_BLACK)
    self.state = st + 1
  elseif st == S.WAIT_FADE_IN_TO_NEW_MON then
    self:dispcnt(0, false, false, true)
    if not fade.active then self.state = st + 1 end
  elseif st == S.POKEBALL_ARRIVE then
    local pb = self:createSprite({ kind = "pokeball", sheet = "pokeball",
                                   pal = PAL_POKEBALL, priority = 0,
                                   affine = "normal", anims = ANIMS.pokeball,
                                   affines = AFFINES.pokeball,
                                   callback = "pokeballArrive" }, 120, -8, 0)
    pb.data[3] = 74
    Gen3TradeAnim.startAnim(pb, 1)
    Gen3TradeAnim.startAffine(pb, 2)
    self:blendPalettes(lshift(1, 16 + pb.pal), 16, RGB_WHITE)
    self.bouncingBall = pb
    self.state = st + 1
    self.timer = 0
  elseif st == S.FADE_POKEBALL_TO_NORMAL then
    self:beginFade(lshift(1, 16 + self.bouncingBall.pal), 1, 16, 0, RGB_WHITE)
    self.state = st + 1
  elseif st == S.POKEBALL_ARRIVE_WAIT then
    if self.bouncingBall.callback == "dummy" then
      self.state = st + 1
    end
  elseif st == S.SHOW_NEW_MON then
    local m1 = mon[1]
    m1.x = 120
    m1.y = yOffset(self.game, self.monSpecies[1]) + 60
    m1.x2, m1.y2 = 0, 0
    m1.species = self.monSpecies[1]
    Gen3TradeAnim.startAnim(m1, 0)
    -- CreatePokeballSpriteToReleaseMon(mon, pal, 120, 84, 2, 1, 20,
    -- PALETTES_BG | (0xF << 16), species)
    self:loadPalette(self.art.palettes.ball, 256 + PAL_BALL * 16, 16)
    local ball = self:createSprite({ kind = "ball", sheet = "ball",
                                     pal = PAL_BALL, priority = 2,
                                     affine = "double", anims = ANIMS.ball,
                                     affines = AFFINES.ball,
                                     callback = "releaseMon" }, 120, 84, 1)
    ball.data[0] = m1.id
    ball.data[5], ball.data[6] = m1.x, m1.y
    m1.x, m1.y = 120, 84
    ball.data[1] = 20
    ball.data[2] = PAL_MON_PARTNER
    ball.fadePalettes = 0xFFFFF
    m1.invisible = true
    self:destroySprite(self.bouncingBall)
    self.state = st + 1
  elseif st == S.NEW_MON_MSG then
    self:dispcnt(0, true, false, true)
    self:say("arrived")
    self.state = S.DELAY_FOR_MON_ANIM
    self.timer = 0
  elseif st == S.DELAY_FOR_MON_ANIM then
    self.timer = self.timer + 1
    if self.timer > 60 then
      -- FireRed plays the cry here; Emerald's played when the ball opened
      if not self.art.releaseAnimates
         and not (self.received and (self.received.isEgg or self.received.egg)) then
        self:cry(self.monSpecies[1])
      end
      self.state = S.WAIT_FOR_MON_CRY
      self.timer = 0
    end
  elseif st == S.WAIT_FOR_MON_CRY then
    if self:isCryFinished() then self.state = S.TAKE_CARE_OF_MON end
  elseif st == S.TAKE_CARE_OF_MON then
    self.timer = self.timer + 1
    if self.timer == 10 then
      local fanfare = Music.special(self.game.data, "evolved")
      if fanfare then
        local ok, played = pcall(Music.playOnce, self.game.data, fanfare)
        self.fanfare = ok and played or nil
      end
    end
    if self.timer == 250 then
      self.state = st + 1
      self:say("takeCare")
      self.timer = 0
    end
  elseif st == S.AFTER_NEW_MON_DELAY then
    self.timer = self.timer + 1
    if self.timer == 60 then self.state = st + 1 end
  elseif st == S.CHECK_RIBBONS then
    self.state = st + 1
  elseif st == S.END_LINK_TRADE then
    local input = self.game.input
    if input and input.wasPressed and input:wasPressed("a") then
      self.state = st + 1
    end
  elseif st == S.TRY_EVOLUTION then
    self.state = st + 1
    self:tradeMons()
  elseif st == S.FADE_OUT_END then
    self:beginFade(PALETTES_ALL, 0, 0, 16, RGB_BLACK)
    self.state = st + 1
  elseif st == S.WAIT_FADE_OUT_END then
    if not fade.active then
      self.state = -1
      self:finish()
    end
  end
end

-- ---------------------------------------------------------------------------
-- STATE_TRY_EVOLUTION: TradeMons, then the trade evolution if there is one
-- ---------------------------------------------------------------------------
function Gen3TradeAnim:tradeMons()
  local onTrade = self.opts.onTrade
  local evolving
  if onTrade then
    local ok, res = pcall(onTrade)
    if ok then evolving = res end
  end
  if evolving then
    -- TradeEvolutionScene returns to CB2_InGameTrade, which carries on at
    -- STATE_FADE_OUT_END; the scene is held there until the evolution
    -- screen hands back
    self.holdForEvolution = true
    evolving(function() self.holdForEvolution = false end)
  end
end

function Gen3TradeAnim:finish()
  if self.done then return end
  self.done = true
  pcall(Music.restoreMap, self.game.data)
  local stack = self.game.stack
  if stack and stack.top and stack:top() == self then
    stack:pop()
  elseif stack and stack.pop then
    -- the screen is the one that pushed itself; pop it wherever it is
    local ok = pcall(function()
      if stack.remove then stack:remove(self) else stack:pop() end
    end)
    local _ = ok
  end
  if self.opts.onDone then self.opts.onDone() end
end

-- ---------------------------------------------------------------------------
-- the frame: CB2_InGameTrade, then the VBlank
-- ---------------------------------------------------------------------------
function Gen3TradeAnim:step()
  if self.done then return end
  if not self.art or not getShaders() then
    -- NOTHING TO DRAW WITH (a cache imported before the trade art stage, or
    -- a renderer without shaders): the trade still happens, at once, and the
    -- evolution after it -- the bare swap this special always made
    if not self.fallbackTraded then
      self.fallbackTraded = true
      self:tradeMons()
    end
    if not self.holdForEvolution then self:finish() end
    return
  end
  if self.holdForEvolution then return end
  if self.initFrames > 0 then
    self.initFrames = self.initFrames - 1
    self.frame = self.frame + 1
    return
  end
  self:stateMachine()
  if self.done then return end
  self:runTasks()
  -- AnimateSprites: each sprite's callback, then its animation
  local ids = {}
  for id in pairs(self.sprites) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local spr = self.sprites[id]
    if spr then
      local cb = CB[spr.callback] or CB.dummy
      cb(self, spr)
      if self.sprites[id] == spr then Gen3TradeAnim.animateSprite(spr) end
    end
    if spr and spr.monAnim then pcall(spr.monAnim.update, spr.monAnim, 1 / 60) end
  end
  self:updateFade()
  -- the fanfare: PlayFanfare pauses the scene's song and resumes it
  if self.fanfare and not Music.oneShotPlaying() then
    self.fanfare = nil
    pcall(Music.play, self.game.data, Music.special(self.game.data, "evolution"))
  end
  self.frame = self.frame + 1
end

function Gen3TradeAnim:update()
  self:step()
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------
local function c555(w)
  return band(w, 31) / 31, band(rshift(w, 5), 31) / 31, band(rshift(w, 10), 31) / 31
end

function Gen3TradeAnim:refreshPalette()
  if not self.paletteDirty or self.fade.transferDisabled then return end
  local d = self.palData
  for i = 0, 255 do
    local r, g, b = c555(self.fad[i])
    d:setPixel(i, 0, r, g, b, 1)
    r, g, b = c555(self.fad[256 + i])
    d:setPixel(i, 1, r, g, b, 1)
  end
  self.palTex:replacePixels(d)
  self.paletteDirty = false
end

-- back to front: BuildOamBuffer sorts by priority then subpriority, and the
-- lower OAM slot wins a tie -- the lower sprite id
local function drawOrder(sprites)
  local list = {}
  for _, s in pairs(sprites) do
    if not s.invisible then list[#list + 1] = s end
  end
  table.sort(list, function(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    if a.subpriority ~= b.subpriority then return a.subpriority > b.subpriority end
    return a.id > b.id
  end)
  return list
end

function Gen3TradeAnim:drawSprite(spr, sh)
  local g = love.graphics
  local sx, sy = 1, 1
  if spr.affineMode then
    sx, sy = spr.xScale / 256, spr.yScale / 256
  else
    if spr.flipH then sx = -1 end
    if spr.flipV then sy = -1 end
  end
  local cx, cy = spr.x + spr.x2, spr.y + spr.y2
  if spr.kind == "mon" then
    local img = self.monImg[spr.party]
    if not img then return end
    local blend = self.monBlend[spr.pal] or { coeff = 0, color = 0 }
    local r, gg, b = c555(blend.color)
    sh.mon:send("target", { r, gg, b })
    sh.mon:send("coeff", blend.coeff)
    g.setShader(sh.mon)
    local w, h = img:getDimensions()
    local t = spr.monAnim and spr.monAnim:transform()
    local dx, dy, msx, msy, rot = 0, 0, 1, 1, 0
    if t then dx, dy, msx, msy, rot = t.dx or 0, t.dy or 0, t.sx or 1, t.sy or 1, t.rot or 0 end
    if math.abs(sx) < 1 / 256 or math.abs(sy) < 1 / 256 then return end
    g.draw(img, math.floor(cx + dx), math.floor(cy + dy), rot, sx * msx,
           sy * msy, w / 2, h / 2)
    return
  end
  local sheet = SHEETS[spr.sheet]
  local img = sheet and self.img[sheet.key]
  if not img then return end
  local frame = math.floor((spr.image or 0) / sheet.tiles)
  local quad = self.quads and self.quads[spr.sheet .. ":" .. frame]
  if not quad then
    self.quads = self.quads or {}
    local iw, ih = img:getDimensions()
    quad = love.graphics.newQuad(0, frame * sheet.h, sheet.w, sheet.h, iw, ih)
    self.quads[spr.sheet .. ":" .. frame] = quad
  end
  sh.index:send("row", 0.75)
  sh.index:send("bank", spr.pal)
  sh.index:send("alpha", spr.semi and 0.5 or 1.0)
  g.setShader(sh.index)
  if math.abs(sx) < 1 / 256 or math.abs(sy) < 1 / 256 then return end
  g.draw(img, quad, cx, cy, 0, sx, sy, sheet.w / 2, sheet.h / 2)
end

-- BG2's sample: the text layers by scroll, the GBA by its affine matrix
function Gen3TradeAnim:bg2Params()
  local r = self.reg
  if r.mode == 1 then
    -- DoBgAffineSet(texX << 8, texY << 8, scrX, scrY, sXY, sXY, 0):
    -- pa = pd = sXY (8.8), pb = pc = 0; dx = texX*256 - pa*scrX
    local pa = self.sXY / 256
    local refX = self.texX - pa * self.scrX
    local refY = self.texY - pa * self.scrY
    return self.img.bg_affine, true, { pa, 0, 0, pa }, { refX, refY }
  end
  local img = (r.bg2Src == "signal") and self.img.bg_signal or self.img.bg_platform
  return img, false
end

function Gen3TradeAnim:render()
  local sh = getShaders()
  if not (sh and self.canvas) then return end
  local g = love.graphics
  self:refreshPalette()
  g.push("all")
  g.origin()
  -- the OBJ layer
  g.setCanvas(self.objCanvas)
  g.clear(0, 0, 0, 0)
  -- "premultiplied": the alpha byte is a flag (1 normal, 0.5 semi-
  -- transparent) and must not scale the colour on the way in
  g.setBlendMode("replace", "premultiplied")
  sh.index:send("palTex", self.palTex)
  g.setColor(1, 1, 1, 1)
  for _, spr in ipairs(drawOrder(self.sprites)) do self:drawSprite(spr, sh) end
  g.setShader()
  g.setBlendMode("alpha")
  -- BG1 + BG2 + OBJ
  g.setCanvas(self.canvas)
  g.clear(0, 0, 0, 1)
  local r = self.reg
  local c = sh.composite
  c:send("palTex", self.palTex)
  local bg1 = (r.bg1Src == "closeup") and self.img.bg_closeup or self.img.bg_gba
  local bg1On = r.bg1 and bg1 ~= nil
  c:send("bg1On", bg1On and 1 or 0)
  if bg1 then
    c:send("bg1Tex", bg1)
    c:send("bg1Size", { bg1:getDimensions() })
  else
    c:send("bg1Tex", self.palTex)
    c:send("bg1Size", { 256, 2 })
  end
  c:send("bg1Ofs", { self.bg1hofs % 512, self.bg1vofs % 512 })
  local bg2, affine, mat, ref = self:bg2Params()
  c:send("bg2On", (r.bg2 and bg2) and 1 or 0)
  c:send("bg2Tex", bg2 or self.palTex)
  c:send("bg2Size", bg2 and { bg2:getDimensions() } or { 256, 2 })
  c:send("bg2Ofs", { self.bg2hofs % 512, self.bg2vofs % 512 })
  c:send("bg2Affine", affine and 1 or 0)
  c:send("bg2Mat", mat or { 1, 0, 0, 1 })
  c:send("bg2Ref", ref or { 0, 0 })
  local b = r.blend
  c:send("blendOn", b.on and 1 or 0)
  c:send("tgt1", b.t1)
  c:send("tgt2", b.t2)
  c:send("ev", { b.eva, b.evb })
  c:send("winOn", r.win.on and 1 or 0)
  c:send("win", { r.win.left, r.win.right, r.win.top, r.win.bottom })
  g.setShader(c)
  g.setColor(1, 1, 1, 1)
  g.draw(self.objCanvas, 0, 0)
  g.setShader()
  -- BG0, priority 0, above every trade sprite: the battle text box and
  -- window 0 at tiles (2,15), 26 x 4, filled with colour 15
  if r.bg0 and self.img.bg_textbox and not r.win.on then
    sh.index:send("row", 0.25)
    sh.index:send("bank", 0)
    sh.index:send("alpha", 1)
    g.setShader(sh.index)
    g.draw(self.img.bg_textbox, 0, 0)
    g.setShader()
    local fr, fg, fb = c555(self.fad[15])
    g.setColor(fr, fg, fb, 1)
    g.rectangle("fill", 16, 120, 208, 32)
    if self.windowText and self.windowText ~= "" then
      local L = self.art.textLayout or {}
      local tr, tg, tb = c555(self.fad[1])
      local sr, sg, sb = c555(self.fad[6])
      Font.pushStyle({ text = { tr, tg, tb, 1 }, shadow = { sr, sg, sb, 1 } })
      g.setColor(1, 1, 1, 1)
      local y = 120 + (L.y or 2)
      local advance = (L.maxLetterHeight or 16) + (L.lineSpacing or 0)
      for line in (self.windowText .. "\n"):gmatch("(.-)\n") do
        Font.draw(line, 16 + (L.x or 0), y)
        y = y + advance
      end
      Font.popStyle()
    end
  end
  g.pop()
end

function Gen3TradeAnim:draw()
  local g = love.graphics
  if not self.canvas or (self.initFrames or 0) > 2 then
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", 0, 0, GBA_W, GBA_H)
    g.setColor(1, 1, 1, 1)
    return
  end
  self:render()
  g.setColor(1, 1, 1, 1)
  g.draw(self.canvas, 0, 0)
end

return Gen3TradeAnim
