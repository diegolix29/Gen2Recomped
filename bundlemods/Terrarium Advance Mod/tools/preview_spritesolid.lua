-- texlua tools/preview_spritesolid.lua [outdir] [ss]
-- Builds the fixture body for each slot and writes mesh + padded atlas for
-- tools/preview_spritesolid.py to render. No LOVE needed.
local outdir = arg[1] or "/tmp/solid"
local ss = tonumber(arg[2]) or 1
local blur = tonumber(arg[3])
os.execute("mkdir -p " .. outdir)
local S = assert(loadfile("lib/SpriteSolid.lua"))()
local F = assert(loadfile("tools/spritesolid_fixture.lua"))()
local rgba, w, h = F.makeSheet()
local padded = S.padRGBA(rgba, w, h, F.W, F.H, 3)
local f = assert(io.open(outdir .. "/atlas.rgba", "wb")); f:write(padded); f:close()
f = assert(io.open(outdir .. "/atlas.txt", "w")); f:write(w, " ", h, "\n"); f:close()
for slot = 1, 3 do
  local views, layout = F.viewsFor(S, rgba, w, h, slot)
  local t0 = os.clock()
  local r, why = S.build(views, layout, { ss = ss, blur = blur })
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
  f = assert(io.open(outdir .. "/mesh" .. slot .. ".txt", "w")); f:write(table.concat(out, "\n")); f:close()
end
