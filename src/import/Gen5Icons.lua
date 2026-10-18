-- BLACK AND WHITE'S PARTY ICONS (/a/0/0/7; bw_ui_map.md):
--
--   0          the icon palettes, 48 colours -- three 16-colour rows
--   1-6        the icons' cells and animations (32 x 32, two frames)
--   7 + 2N     species N's icon, 32 x 64 (both frames stacked)
--   8 + 2N     its female / alternate form, empty when it has none
--
-- WHICH OF THE THREE ROWS AN ICON WEARS is a table the cartridge keeps
-- somewhere this port has not found (it is not a byte or halfword run in the
-- ARM9 or any overlay). Until it is, the row is CHOSEN: the icon's average
-- colour under each candidate row is compared with the average colour of the
-- species' own battle picture (pokegra +0 on +18), and the nearest wins. A Pokemon's icon and
-- its battle picture are the same colours by design, so this lands on the
-- cartridge's row in practice; the record says it was chosen.
--
-- Written as Platinum's icons are (`gen4_species_sprites.icons`), so the
-- party menu, the PC and every other reader find them the same way.

local I = {}

I.PATH = "/a/0/0/7"
I.FIRST = 7
I.SPECIES = 649

local function dist(a, b)
  local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
  return dr * dr + dg * dg + db * db
end

function I.build(x)
  local G = require("src.import.Gen4Graphics")
  local Lz = require("src.import.Gen5Lz")
  local Narc = require("src.import.NarcArchive")
  local arc = Narc.parse(x.rom:read(I.PATH) or "")
  local gra = Narc.parse(x.rom:read("/a/0/0/4") or "")
  if not arc then return nil end
  local function m(a, i)
    local b = a and a:get(i)
    if not b or #b == 0 then return nil end
    if Lz.isCompressed(b) then b = Lz.decompress(b) elseif G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local pal = G.palette(m(arc, 0))
  if not pal then return nil end
  local function row(r) local o = {} for k = 1, 16 do o[k] = pal[r * 16 + k] or { 0, 0, 0 } end return o end
  local rows = { row(0), row(1), row(2) }
  local out = { bySpecies = {}, frameHeight = 32, frames = 2, width = 32, count = 0,
                paletteChosen = true, source = "ROM:/a/0/0/7 (7 + 2N; palette row matched to the battle palette)" }
  for id = 1, I.SPECIES do
    local sheet = G.tiles(m(arc, I.FIRST + id * 2))
    if sheet and sheet.pixels then
      -- the battle picture's own average colour (its pixels, not its palette)
      local battle = G.palette(m(gra, id * 20 + 18))
      local still = G.tiles(m(gra, id * 20))
      local function average(pixels, colours)
        local r, g, b, n = 0, 0, 0, 0
        for i = 1, #pixels do
          local byte = pixels:byte(i)
          for _, idx in ipairs({ byte % 16, math.floor(byte / 16) }) do
            local c = idx > 0 and colours[idx + 1]
            if c then r, g, b, n = r + c[1], g + c[2], b + c[3], n + 1 end
          end
        end
        if n == 0 then return nil end
        return { r / n, g / n, b / n }
      end
      local target = battle and still and still.pixels and average(still.pixels, battle)
      local best, bestScore = 1, math.huge
      if target then
        for r = 1, 3 do
          local avg = average(sheet.pixels, rows[r])
          local score = avg and dist(avg, target) or math.huge
          if score < bestScore then best, bestScore = r, score end
        end
      end
      local cells = {}
      for t = 0, sheet.count - 1 do cells[t + 1] = { tile = t, palette = 0 } end
      local image = G.compose({ width = 32, height = 64, cells = cells }, sheet, rows[best])
      local entry = image and x:saveImage(("pokemon/icon/%03d"):format(id), image, { icon = id, row = best - 1 })
      if entry then
        out.bySpecies[id] = { image = entry.path, frameHeight = 32, row = best - 1 }
        out.count = out.count + 1
      end
    end
  end
  return out
end

return I
