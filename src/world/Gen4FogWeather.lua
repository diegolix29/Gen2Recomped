-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S FOG (OVERWORLD_WEATHER_FOG, 14) AND DEFOG CLEARING IT.
--
-- The weather task ov5_021DAEC0 (pokeplatinum src/overlay005/ov5_021D5EB8.c):
--   * the 3D engine's fog: slope 6, offset 30037, GX_RGB(31, 31, 31)
--     (ov5_021D7308 -> ov5_021D7384); density table entry i = 4i when full
--   * BG2: weather_sys set 6 (palette 51, char 45, screen 47 -- a flat white
--     layer, gen4_pt_field_fx.fogLayer), alpha-blended over BG0 (the 3D) and
--     the backdrop at eva / 16 against 16 - eva (ov5_021D64E4,
--     G2_SetBlendAlpha(BG2, BG0 | BD, eva, 16 - eva)); eva 9 in full swing
--   A map that loads with the fog has it at once (state 2: eva 9, the table
--   full).
--
-- DEFOG: FieldMoves_UseDefogFromMenu -> PlayHMCutIn, DoDefogFunc SET_ACTIVE,
-- SEQ_SE_DP_FBRADE, ScrCmd_0C4 -> ov5_021D5F7C(CLEAR): the fog task is told to
-- end (unk_BA6 = 5) and runs states 3..5:
--   * eva 9 -> 0 over 30 field frames (ov5_021D64FC(.., 9, 0, 30): eva =
--     9 - 9k / 30 for k = 0..30)
--   * the density table thins one step a frame for 127 frames (ov5_021D749C
--     (.., 1, FALSE) -> ov5_021D7534: v = (127 - n) / 4, entries above v are
--     (i - v) * 4, the rest keep the 4 they last had)
--   * when both are done the 3D fog is switched off and the weather unloads.
-- The fog depth is drawn by Gen4DepthFog through `depthRow`; the layer by
-- `draw`, the overworld's screen-weather callback.

local M = {}

M.ID = 14
M.ROW = { slope = 6, offset = 30037, rgb = { 31, 31, 31 } }
M.EVA = 9
M.EVA_FRAMES = 30
M.TABLE_FRAMES = 127
M.TICKS_PER_FRAME = 2

local function Game() return package.loaded["src.core.Game"] end

local function platinum()
  local G = Game()
  local data = G and G.data
  if not (data and data.isGen4Cache) then return false end
  local okV, GV = pcall(require, "src.core.GameVersion")
  if okV and GV.isGen5 and GV.isGen5() then return false end
  local v = data.gen4_version
  return not (v and v.family == "hgss")
end

local function layerPath()
  local G = Game()
  local t = G and G.data and G.data.gen4_pt_field_fx
  return t and t.fogLayer or nil
end

M.state = nil

-- eva and the table's shift at field frame f of the clearing
function M.fade(f)
  f = math.max(0, math.floor(f))
  local k = math.min(f, M.EVA_FRAMES)
  -- ov5_021D650C: (to - from) * k / frames, C division (toward zero)
  local q = -M.EVA * k / M.EVA_FRAMES
  local eva = M.EVA + (q < 0 and math.ceil(q) or math.floor(q))
  -- ov5_021D7534 runs with n = 127 - frame before its decrement
  local n = math.max(1, M.TABLE_FRAMES - math.min(f, M.TABLE_FRAMES - 1))
  local shift = math.floor((127 - n) / 4)
  local done = f >= M.EVA_FRAMES and f >= M.TABLE_FRAMES
  return eva, shift, done
end

-- every frame the overworld draws its weather; true while there is fog to draw
function M.update(ow)
  if not (ow and platinum() and layerPath()) then M.state = nil return false end
  local G = Game()
  local active = tonumber(G and G.save and G.save.gen4WeatherActive)
  local mapId = ow.map and ow.map.id
  local frame = ow.weatherFrame or 0
  local st = M.state
  if st and st.map ~= mapId then st = nil end
  if active == M.ID then
    st = { map = mapId, eva = M.EVA, shift = 0 }
  elseif st and not st.clearing then
    -- the weather changed under a standing player: Defog (ScrCmd_0C4)
    st.clearing, st.start = true, frame
  end
  if st and st.clearing then
    local eva, shift, done = M.fade((frame - st.start) / M.TICKS_PER_FRAME)
    st.eva, st.shift = eva, shift
    if done then st = nil end
  end
  M.state = st
  return st ~= nil
end

-- Gen4DepthFog's row while the fog is up or thinning
function M.depthRow()
  local st = M.state
  if not st then return nil end
  return { slope = M.ROW.slope, offset = M.ROW.offset, rgb = M.ROW.rgb, shift = st.shift or 0 }
end

local images = {}
local function image(path)
  if images[path] ~= nil then return images[path] or nil end
  local ok, img = pcall(require("src.render.Assets").image, path)
  images[path] = ok and img or false
  return ok and img or nil
end

-- Renderer.screenWeather: BG2 at eva / 16 over the field
function M.draw(w, h)
  local st = M.state
  if not st or (st.eva or 0) <= 0 then return st ~= nil end
  local img = layerPath() and image(layerPath())
  if not img then return false end
  local g = love.graphics
  local s = h / 192
  local left = (w - 256 * s) / 2
  g.push("all")
  g.setColor(1, 1, 1, st.eva / 16)
  local q = g.newQuad(-left / s, 0, w / s, h / s, 256, 256)
  img:setWrap("repeat", "repeat")
  g.draw(img, q, 0, 0, 0, s, s)
  g.pop()
  return true
end

return M
