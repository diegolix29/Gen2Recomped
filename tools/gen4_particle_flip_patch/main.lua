-- tools/gen4_particle_flip_patch/main.lua
--
-- Adds each particle texture's FLIP bits (SPLTextureParam bits 14-15, read by
-- Gen4Particle.textures) to an EXISTING cache's gen4_particles records, so a
-- move's quarter-circle textures tile into rings without a re-import.
--
--   love tools/gen4_particle_flip_patch <platinum .nds> <cache dir>

function love.load(args)
  local ok, err = xpcall(function()
    local romPath, cacheDir = args[1], args[2]
    assert(romPath and cacheDir, "usage: love tools/gen4_particle_flip_patch <rom> <cache dir>")
    local P = require("src.import.Gen4Particle")
    local Narc = require("src.import.NarcArchive")
    local G = require("src.import.Gen4Graphics")
    local rom = assert(require("src.import.NdsRom").open(romPath))
    local path = cacheDir .. "/gen4_particles.lua"
    local index = assert(dofile(path))
    local sources = {
      { key = "move", path = P.ARCHIVE_MOVES },
      { key = "ball", path = P.ARCHIVE_BALLS },
      { key = "opening", path = P.ARCHIVE_FIELD, first = 4, last = 4 },
    }
    local flipped, seen = 0, 0
    for _, src in ipairs(sources) do
      local raw = rom:read(src.path)
      local arc = raw and Narc.parse(raw)
      if arc then
        for member = src.first or 0, src.last or (arc.count - 1) do
          local data = arc:get(member)
          if data and G.isCompressed(data) then data = G.decompress(data) end
          local list = data and P.textures(data)
          local entry = index.effects and index.effects[src.key .. "_" .. member]
          if list and entry and entry.textures then
            for i, t in ipairs(list) do
              local rec = entry.textures[i]
              if rec then
                seen = seen + 1
                rec.flipS = t.flipS or nil
                rec.flipT = t.flipT or nil
                if t.flipS or t.flipT then flipped = flipped + 1 end
              end
            end
          end
        end
      end
    end
    local f = assert(io.open(path, "wb"))
    f:write(require("src.import.LuaWriter").encode(index))
    f:close()
    print(("%d textures read, %d flipped, written to %s"):format(seen, flipped, path))
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit()
end
