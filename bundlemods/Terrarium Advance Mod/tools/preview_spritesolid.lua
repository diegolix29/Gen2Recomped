-- texlua tools/preview_spritesolid.lua [outdir] [ss] [blur] [chibi] [wrap]
-- Builds the fixture body for each slot and writes mesh + that body's own baked
-- atlas for tools/preview_spritesolid.py. No LOVE needed. SOLID=path/to/old.lua
-- renders with another SpriteSolid (to compare builds).
local outdir = arg[1] or "/tmp/solid"
local ss = tonumber(arg[2]) or 1
local blur = tonumber(arg[3])
local wrap = tonumber(arg[5])
os.execute("mkdir -p " .. outdir)
local S = assert(loadfile(os.getenv("SOLID") or "lib/SpriteSolid.lua"))()
local F = assert(loadfile("tools/spritesolid_fixture.lua"))()
local rgba, w, h
if arg[4] == "chibi" then rgba, w, h = F.makeChibi() else rgba, w, h = F.makeSheet() end
local padded = S.padRGBA(rgba, w, h, F.W, F.H, 4)
local legacy = os.getenv("SOLID") ~= nil     -- the shipped build samples the sheet itself
if legacy then
  local f = assert(io.open(outdir .. "/atlas.rgba", "wb")); f:write(padded); f:close()
  f = assert(io.open(outdir .. "/atlas.txt", "w")); f:write(w, " ", h, "\n"); f:close()
end
for slot = 1, 3 do
  local views, layout = F.viewsFor(S, rgba, w, h, slot, padded)
  local t0 = os.clock()
  local r, why = S.build(views, layout, { ss = ss, blur = blur, wrap = wrap })
  assert(r, why)
  print(string.format("slot %d ss=%d: %d verts, %d tris, %.0f ms", slot, ss,
    r.vertexCount, r.triangleCount, (os.clock() - t0) * 1000))
  local out = {}
  for _, v in ipairs(r.verts) do
    out[#out + 1] = string.format("v %.5f %.5f %.5f %.6f %.6f %.4f", v[1], v[2], v[3], v[4], v[5], v[6])
  end
  for i = 1, #r.map, 3 do
    out[#out + 1] = string.format("f %d %d %d", r.map[i] - 1, r.map[i + 1] - 1, r.map[i + 2] - 1)
  end
  local f = assert(io.open(outdir .. "/mesh" .. slot .. ".txt", "w")); f:write(table.concat(out, "\n")); f:close()
  if r.atlas then
    f = assert(io.open(outdir .. "/atlas" .. slot .. ".rgba", "wb")); f:write(r.atlas); f:close()
    f = assert(io.open(outdir .. "/atlas" .. slot .. ".txt", "w")); f:write(r.atlasW, " ", r.atlasH, "\n"); f:close()
  end
end
