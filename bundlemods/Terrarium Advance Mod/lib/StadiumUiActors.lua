-- StadiumUiActors: Pokemon Stadium 1 / 2 models as portable menu actors.
--
-- The menus (Summary, Pokedex, PC, party pods) draw 3D Pokemon through one
-- contract, the same one lib/PokemonActors exports:
--
--   service.acquire(source, dex, variant, opts) -> actor | nil
--   service.withRenderer(vp, fn, opts)          -> ok, ...
--   actor:update(dt) / :idle() / :matrix(...) / :build() / :draw(matrix)
--
-- StadiumMon already speaks almost all of that; what it lacks is a renderer
-- that works OUTSIDE the overworld pass. StadiumRig:draw goes through
-- Voxel3D, which only draws inside Voxel3D.beginScene (the world camera, the
-- world canvas). A menu has its own canvas and camera, so this module draws
-- the rig's skinned meshes with a small shader of its own: same vertex
-- format (Voxel3D.FORMAT), same baked per-vertex shade, no world effects.
--
-- Covers National Dex 1-251 (StadiumPack's range). Which game a species
-- comes from is StadiumPack's decision (PREFER_STADIUM2: Stadium 2 first).

local V = ...
local unpack = table.unpack or unpack

local S = { version = 1, SELECTED = "selected", id = "terrarium:stadium-models" }

local Mon, Pack
local function deps()
  if Mon then return true end
  local okM, m = pcall(V.require, "StadiumMon")
  local okP, p = pcall(V.require, "StadiumPack")
  if okM and m and okP and p then Mon, Pack = m, p return true end
  return false
end

-- ------- the shader

local SHADER_SRC = [[
  uniform mat4 uViewProj;
  uniform mat4 uModel;
  varying float vShade;
#ifdef VERTEX
  attribute float VertexShade;
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vShade = abs(VertexShade);
    return uViewProj * (uModel * vec4(vertex_position.xyz, 1.0));
  }
#endif
#ifdef PIXEL
  vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
    vec4 c = Texel(tex, uv) * color;
    if (c.a < 0.08) discard;
    float s = clamp(vShade, 0.45, 1.15);
    return vec4(c.rgb * s, c.a);
  }
#endif
]]

local shader, shaderFailed
local function getShader()
  if shader then return shader end
  if shaderFailed then return nil end
  local ok, sh = pcall(love.graphics.newShader, SHADER_SRC)
  if ok and sh then shader = sh return sh end
  shaderFailed = true
  if V.mod and V.mod.log and V.mod.log.warn then
    pcall(V.mod.log.warn, V.mod.log, "StadiumUiActors: shader failed: %s", tostring(sh))
  end
  return nil
end

local white
local function whiteTexture()
  if white then return white end
  local ok, data = pcall(love.image.newImageData, 1, 1)
  if not ok then return nil end
  data:setPixel(0, 0, 0.85, 0.85, 0.85, 1)
  white = love.graphics.newImage(data)
  return white
end

-- ------- availability

function S.available(source, dex)
  if not deps() then return false end
  dex = math.floor(tonumber(dex) or 0)
  if dex < 1 or dex > 251 then return false end
  local ok, present = pcall(Pack.available, dex)
  return ok and present == true
end

-- No resident cache to report: a pack loads in one call, and StadiumPack
-- keeps its own small LRU. Report "resident" so the UI acquires directly.
function S.peek(source, dex)
  if S.available(source, dex) then return { resident = true } end
  return { resident = false, missing = true }
end

-- ------- actors

local Actor = {}
Actor.__index = Actor

function S.acquire(source, dex, variant, opts)
  if not deps() then return nil end
  dex = math.floor(tonumber(dex) or 0)
  if dex < 1 or dex > 251 then return nil end
  local mon = Mon.new("external")
  local ok, ready = pcall(mon.setSpecies, mon, dex, variant == "shiny")
  if not (ok and ready) then
    pcall(mon.release, mon)
    return nil
  end
  return setmetatable({ mon = mon, dex = dex, variant = variant,
    providerId = S.id }, Actor)
end

S.acquireCached = S.acquire

function Actor:update(dt) if self.mon then pcall(self.mon.update, self.mon, dt or 0) end end
function Actor:idle() if self.mon then pcall(self.mon.play, self.mon, "idle") end end
function Actor:play(state) if self.mon then return pcall(self.mon.play, self.mon, state or "idle") end end
function Actor:spawn() end
function Actor:worldHeight() return self.mon and self.mon:worldHeight() or 14 end
function Actor:worldRadius()
  local r = self.mon and self.mon:worldRadius() or 0
  return r > 0 and r or self:worldHeight() * 0.45
end
function Actor:matrix(x, gy, z, fx, fz)
  return self.mon and self.mon:matrix(x or 0, gy or 0, z or 0, fx, fz) or nil
end
function Actor:build()
  if not self.mon then return false end
  local ok, built = pcall(self.mon.build, self.mon)
  return ok and built ~= false
end
function Actor:release()
  if self.mon then pcall(self.mon.release, self.mon) end
  self.mon = nil
end

local current -- the shader bound by withRenderer, or nil outside it

function Actor:draw(matrix)
  local mon, sh = self.mon, current
  local rig = mon and mon.rig
  if not (rig and sh and matrix) then return false end
  pcall(sh.send, sh, "uModel", "row", matrix)
  local g = love.graphics
  local additive
  for _, part in ipairs(rig.parts or {}) do
    if part.prim and part.prim.additive then
      additive = additive or {}
      additive[#additive + 1] = part
    else
      local tex = part.texture or part.neutralTexture or whiteTexture()
      if tex then pcall(part.mesh.setTexture, part.mesh, tex) end
      pcall(g.draw, part.mesh)
    end
  end
  if additive then
    g.setBlendMode("add")
    for _, part in ipairs(additive) do
      if part.texture then
        pcall(part.mesh.setTexture, part.mesh, part.texture)
        pcall(g.draw, part.mesh)
      end
    end
    g.setBlendMode("alpha")
  end
  return true
end

-- ------- the renderer

function S.withRenderer(vp, fn, opts)
  local sh = getShader()
  if not (sh and type(vp) == "table" and type(fn) == "function") then
    return false, "stadium ui renderer unavailable"
  end
  local g = love.graphics
  g.push("all")
  g.setShader(sh)
  pcall(sh.send, sh, "uViewProj", "row", vp)
  g.setDepthMode("lequal", true)
  g.setMeshCullMode("none")
  g.setColor(1, 1, 1, 1)
  current = sh
  local results = { pcall(fn) }
  current = nil
  g.pop()
  if not results[1] then return false, results[2] end
  return true, select(2, unpack(results))
end

return S
