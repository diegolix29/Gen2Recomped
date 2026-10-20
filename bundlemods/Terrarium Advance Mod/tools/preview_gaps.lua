-- texlua tools/preview_gaps.lua <outdir> <x|z> [oldSolid.lua]
-- Exports the torso-over-two-legs figure (1 px gap) built three ways, as slots
-- 1..3: [1] an older SpriteSolid (arg 3), [2] only the 10% sharpen, [3] the default.
-- Render a slot with tools/preview_spritesolid.py.
local outdir, mode = arg[1] or "/tmp/gp", arg[2] or "x"
os.execute("mkdir -p " .. outdir)
local F = assert(loadfile("tools/spritesolid_fixture.lua"))()
local New = assert(loadfile("lib/SpriteSolid.lua"))()
local Old = arg[3] and assert(loadfile(arg[3]))() or New
local variants = {
  { Old, nil },
  { New, { keepGaps = false } },
  { New, nil },
}
for slot, v in ipairs(variants) do
  local r = F.legFigure(v[1], 33, 1, mode, v[2])
  local out = {}
  for _, vert in ipairs(r.verts) do
    out[#out + 1] = string.format("v %.5f %.5f %.5f %.6f %.6f %.4f", vert[1], vert[2], vert[3], vert[4], vert[5], vert[6])
  end
  for i = 1, #r.map, 3 do out[#out + 1] = string.format("f %d %d %d", r.map[i] - 1, r.map[i + 1] - 1, r.map[i + 2] - 1) end
  local f = assert(io.open(outdir .. "/mesh" .. slot .. ".txt", "w")); f:write(table.concat(out, "\n")); f:close()
  f = assert(io.open(outdir .. "/atlas" .. slot .. ".rgba", "wb")); f:write(r.atlas); f:close()
  f = assert(io.open(outdir .. "/atlas" .. slot .. ".txt", "w")); f:write(r.atlasW, " ", r.atlasH, "\n"); f:close()
end
