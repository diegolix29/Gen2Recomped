-- src/import/Gen5TradeArt.lua -- BLACK AND WHITE'S TRADE DEMO, AS AN NPC TRADE
-- PLAYS IT.
--
-- WHICH DEMO. 0x1BE's field task (ov21 0x021CC390) starts process template
-- 0x021E75A8 of overlay 119 (pokemontrade_proc.c) -- init 0x021DCC39, the
-- variant that sets mode 4 and hands over to overlay 117's state 0x021D4B89.
-- Overlay 117 is the whole NPC demo; its 3D setup calls 0x021E5284 with 1,
-- which takes the archive 0x68 = /a/1/0/4 branch rather than /a/1/0/3's
-- (the link trades' "matome" / "short" scenes). /a/1/0/4 is the INFRARED
-- trade's scene, named for it:
--
--    0-2  RGCN / RLCN / RCSN  the sub screen's background (BG frame 6)
--    3/4  ir_ichi        the camera's position node (BCA 660 frames)
--    5-7  ir_sean        the scene (BCA, BMD, BTA -- 660 frames)
--    8/9  ir_tyushiten   the camera's look-at node
--    10   SPA "12_1"     4 emitters, 3 textures
--    11   the camera's eye, baked: u32 660, u32 0x10000, then 660 x three
--         floats -- (0, 10, 25), (0, 100, 25) on frames 180..418: exactly the
--         ir_ichi node's track, so the camera here reads these two
--    12   the look-at point, the same way: (0, 0, 0) throughout
--
-- THE CLOCK is overlay 117's 0x021D4CE8, one tick a frame against the
-- counter at work+0xF2C (0x021D4480 is `bx lr`, so its literals ARE frames):
--     1 / 2  your Pokemon's sprite paled to white (8, then 16); 4 hidden
--     3      the cell actor at (128, 99) (a/1/0/3 0-3) shown; 598 removed
--     20 / 200 / 350 / 600  particle emitters 2 / 1 / 0 / 2
--     130    the screen fades to white over 20 frames; 180 back over 25
--     250    your Pokemon (sprite 2, doubled) from (-50, -500) to (-50, 300)
--            over 150 frames; 251 theirs (sprite 3) from (60, 300) to
--            (60, -370) over 150
--     615    the end of the 3D part; 616 the sprites pale to white
-- and its SE table is ov119 0x021E7794 ({ se, frame } x 22, called from ov117
-- 0x021D50F6): the SEQ_SE_TDEMO_* set with the ball's KON bounces.
--
-- THE TEXT is system bank 159 (ov119 0x021E10F0): #48 "{VAR1} sent over /
-- {VAR2}.", #49 "Take good care of {VAR2}!".

local A = {}

A.PATH = "/a/1/0/4"
A.SCENE = { model = 6, motion = 5, srt = 7 }
A.EYE, A.TARGET = 11, 12
A.PARTICLES = 10
A.BG = { char = 0, palette = 1, screen = 2 }
A.FRAMES = 660
A.END = 616
A.BANK, A.SENT, A.CARE = 159, 48, 49
A.MUSIC = "SEQ_BGM_KOUKAN"
-- { se, frame } -- ov119 0x021E7794
A.SE = {
  { 1921, 32 }, { 1383, 33 }, { 1387, 38 }, { 1387, 45 }, { 1387, 56 }, { 1387, 64 },
  { 1925, 30 }, { 1447, 110 }, { 1933, 130 }, { 1926, 241 }, { 1927, 320 }, { 1455, 364 },
  { 1486, 409 }, { 1427, 484 }, { 1387, 494 }, { 1387, 514 }, { 1387, 528 }, { 1387, 538 },
  { 1387, 547 }, { 1928, 569 }, { 1929, 615 }, { 1925, 605 },
}
-- { frame, emitter } -- ov117 0x021D4D9A..0x021D4E0C (the two at frame -1
-- never fire)
A.EMIT = { { 20, 2 }, { 200, 1 }, { 350, 0 }, { 600, 2 } }
-- the white fades: { frame, to, over }
A.FADES = { { 130, 16, 20 }, { 180, 0, 25 } }
-- the two sprites' flights: { frame, which, from, to, frames, scale }
A.FLIGHTS = {
  { 250, "sending", { -50, -500, 10 }, { -50, 300, 10 }, 150, 2 },
  { 251, "receiving", { 60, 300, -10 }, { 60, -370, -10 }, 150, 1 },
}

local function f32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  if not d then return 0 end
  local bits = a + b * 256 + c * 65536 + d * 16777216
  local sign = bits >= 2 ^ 31 and -1 or 1
  local e = math.floor(bits / 2 ^ 23) % 256
  local m = bits % 2 ^ 23
  if e == 0 then return sign * m * 2 ^ -149 end
  return sign * (1 + m / 2 ^ 23) * 2 ^ (e - 127)
end

-- members 11 / 12: { frames, xyz, xyz, ... } flattened
function A.track(bytes)
  if type(bytes) ~= "string" or #bytes < 8 then return nil end
  local n = bytes:byte(1) + bytes:byte(2) * 256 + bytes:byte(3) * 65536
  if #bytes < 8 + n * 12 then return nil end
  local data = {}
  for i = 0, n * 3 - 1 do data[#data + 1] = f32(bytes, 8 + i * 4) end
  return { frames = n, data = data }
end

function A.build(x)
  local Narc = require("src.import.NarcArchive")
  local G = require("src.import.Gen4Graphics")
  local raw = x.rom:read(A.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local function member(i)
    local b = arc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local out = {
    source = "ROM:" .. A.PATH .. " (overlay 117's NPC demo on overlay 119)",
    frames = A.FRAMES, length = A.END, se = A.SE, emit = A.EMIT, fades = A.FADES,
    flights = A.FLIGHTS, bank = A.BANK, sent = A.SENT, care = A.CARE, music = A.MUSIC,
    images = {},
  }

  -- the scene, packed with its textures, its joint tracks and its SRT
  local Models = require("src.import.Gen4Models")
  local Anim = require("src.import.Gen4Anim")
  local Pack = require("src.import.Gen4ModelPack")
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local bytes = member(A.SCENE.model)
  local parsed = bytes and Nsbmd.parse(bytes)
  local model = parsed and parsed.models and parsed.models[1]
  if model then
    local packed = Pack.pack(model)
    local at = bytes:find("TEX0", 1, true)
    local tex = at and Models.parse(bytes, at - 1)
    local written = {}
    for _, shape in ipairs(packed.shapes) do
      if shape.texture and tex then
        local key = tostring(shape.texture) .. "/" .. tostring(shape.palette)
        if written[key] == nil then
          local ti, pi
          for k, t in ipairs(tex.textures) do if t.name == shape.texture then ti = k end end
          for k, p in ipairs(tex.palettes or {}) do if p.name == shape.palette then pi = k end end
          local image = ti and Models.decode(tex, bytes, ti, pi or 1)
          local saved = image and x:saveImage(("trade5/%s_%d"):format(shape.texture:gsub("[^%w_%-]", "_"), pi or 1), image)
          written[key] = saved and (type(saved) == "table" and saved.path or saved) or false
        end
        shape.image = written[key] or nil
      end
    end
    local scene = { model = packed, records = {} }
    local motionBytes = member(A.SCENE.motion)
    local p2 = motionBytes and Anim.parse(motionBytes)
    local anim = p2 and p2.animations and p2.animations[1]
    if anim then
      local motion = { frames = anim.frames, tracks = {} }
      for _, joint in ipairs(Anim.jointMatrices(motionBytes, anim) or {}) do
        motion.tracks[joint.index] = Anim.packTrack(joint.track)
      end
      scene.motion = motion
    end
    local srtBytes = member(A.SCENE.srt)
    local p3 = srtBytes and Anim.parse(srtBytes)
    local srt = p3 and p3.animations and p3.animations[1]
    if srt then
      scene.records[#scene.records + 1] = { kind = "BTA0", frames = srt.frames,
                                            srt = Anim.textureSrt(srtBytes, srt) }
    end
    out.scene = scene
  end

  -- the camera
  out.eye = A.track(member(A.EYE))
  out.target = A.track(member(A.TARGET))

  -- the particles (as Gen5EvolutionArt reads its SPA)
  local spa = member(A.PARTICLES)
  if spa then
    local P = require("src.import.Gen4Particle")
    local okE, emitters = pcall(P.emitters, spa)
    if okE then out.emitters = emitters end
    for i, texture in ipairs(P.textures(spa) or {}) do
      local saved = x:saveImage(("trade5/particle_%d"):format(i - 1), P.rgba(texture))
      if saved then out.images[("particle_%d"):format(i - 1)] = saved end
    end
    local head = P.header(spa)
    if head then
      out.textures = {}
      local at = head.textureAt
      local function u32(o) local a, b, c, d = spa:byte(o + 1, o + 4); return d and a + b * 256 + c * 65536 + d * 16777216 end
      for i = 1, head.textures do
        local param, total = u32(at + 4), u32(at + 28)
        if not (param and total and total > 0) then break end
        local bits = math.floor(param / 4096) % 16
        out.textures[i] = { repeatS = bits % 2 == 1, repeatT = math.floor(bits / 2) % 2 == 1,
          flipS = math.floor(bits / 4) % 2 == 1, flipT = math.floor(bits / 8) % 2 == 1 }
        at = at + total
      end
    end
  end

  -- the sub screen's background
  local okB, err = pcall(function()
    local tiles = assert(G.tiles(member(A.BG.char)))
    local palette = assert(G.palette(member(A.BG.palette)))
    local map = assert(G.tilemap(member(A.BG.screen)))
    local pic = assert(G.compose(map, tiles, palette))
    out.background = x:saveImage("trade5/background", pic)
  end)
  if not okB then out.backgroundError = tostring(err) end
  return out
end

return A
