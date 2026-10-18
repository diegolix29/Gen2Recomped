-- HEARTGOLD / SOULSILVER'S BAG (/a/0/1/5, overlay 15; the loads are mapped in
-- scratch_claude/hgss_ui_screens_map.md "Bag"), written as `gen4_hgss_bag_art`.
--
-- TOP SCREEN (the main engine; `Bag_Init` swaps the screens):
--   top_back_<m|f>   BG3 screen 94 (blue, a boy) / 93 (pink, a girl) on char 7
--   top_panel        BG2 screen 54, the grey description panel, y 152..191
--   palette          member 8 over the whole BG palette, 17 over row 13
--   the bag          BG0 is 3D: model 55 (boy) / 74 (girl), one BCA0 a pocket
--                    (65+p / 84+p) -- packed here as `model_<m|f>` with the
--                    joint tracks of each pocket's animation
--
-- TOUCH SCREEN:
--   touch_panel_<p>   BG6 screen 39 (the six dotted item slots, the header)
--   touch_grid_<p>    BG5 screen 43 (the six buttons over them), char 46
--   palette           member 38, rows 8-11 from member 8; row 0 is the
--                     pocket's colour, member 41 row p (`GetPlttData` 41)
--   sprite_<a>[_p]    char 51 / pal 47 / cell 49 / anim 50: the first frame
--                     of animation a. The eight pocket tabs (anims 0-7) wear
--                     their own palette row, so `sprite_<p>` is in row p.

local A = {}

A.PATH = "/a/0/1/5"
A.POCKETS = 8
A.SPRITE_ANIMS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 13, 16, 19, 20, 22, 25, 27, 31 }
A.MODEL = { m = 55, f = 74 }
A.POCKET_ANIM = { m = 65, f = 84 }

local function copy(colours)
  local out = {}
  for i = 1, 256 do out[i] = colours and colours[i] or { 0, 0, 0 } end
  return out
end

local function put(into, from, at, rows, fromRow)
  for k = 1, rows * 16 do
    local c = from and from[(fromRow or 0) * 16 + k]
    if c then into[at * 16 + k] = c end
  end
end

function A.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local CellAnim = require("src.import.Gen4CellAnim")
  local raw = rom:read(A.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil end
  local function m(i) local b = arc:get(i); if b and G.isCompressed(b) then b = G.decompress(b) end return b end
  local out = {}

  local top = copy(G.palette(m(8)))
  put(top, G.palette(m(17)), 13, 1)
  local chars7 = G.tiles(m(7))
  local function bg(key, screen, sheet, pal)
    local map = G.tilemap(m(screen))
    local img = map and sheet and G.compose(map, sheet, pal)
    if img and img.height > 192 then img = { width = img.width, height = 192, rgba = img.rgba:sub(1, img.width * 192 * 4) } end
    out[key] = img
  end
  bg("top_back_m", 94, chars7, top)
  bg("top_back_f", 93, chars7, top)
  bg("top_panel", 54, chars7, top)

  local sub = copy(G.palette(m(38)))
  put(sub, G.palette(m(8)), 8, 4)
  local pocketColours = G.palette(m(41))
  local chars46 = G.tiles(m(46))
  for p = 0, A.POCKETS - 1 do
    local pal = copy(sub)
    put(pal, pocketColours, 0, 1, p)
    bg("touch_panel_" .. p, 39, chars46, pal)
    bg("touch_grid_" .. p, 43, chars46, pal)
    bg("touch_actions_" .. p, 45, chars46, pal)
  end

  local sheet, objPal = G.tiles(m(51)), G.palette(m(47))
  local bank, anim = Cells.parse(m(49), G), CellAnim.parse(m(50), G)
  if sheet and objPal and bank then
    local function cellOf(a)
      local frames = anim and CellAnim.frames(anim, a)
      return frames and frames[1] and bank.cells[frames[1].cell + 1]
    end
    local function save(key, cell, pal)
      local pic = cell and Cells.assemble(cell, sheet, pal, bank, G)
      if pic then pic.originX, pic.originY = Cells.extent(cell); out[key] = pic end
    end
    for _, a in ipairs(A.SPRITE_ANIMS) do
      local cell = cellOf(a)
      if a < A.POCKETS then
        -- the tab's template puts it in palette row a, whatever its cell says
        local pal = {}
        for k = 1, 256 do pal[k] = objPal[a * 16 + (k - 1) % 16 + 1] end
        save("sprite_" .. a, cell, pal)
      else
        save("sprite_" .. a, cell, objPal)
      end
    end
  end
  return out
end

-- the 3D bag: { m = packed, f = packed }, each with `pockets[p] = tracks`
function A.models(rom, saveImage)
  local G = require("src.import.Gen4Graphics")
  local raw = rom:read(A.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil end
  local function m(i) local b = arc:get(i); if b and G.isCompressed(b) then b = G.decompress(b) end return b end
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local Pack = require("src.import.Gen4ModelPack")
  local Models = require("src.import.Gen4Models")
  local Anim = require("src.import.Gen4Anim")
  local out = {}
  for who, member in pairs(A.MODEL) do
    local bytes = m(member)
    local parsed = bytes and Nsbmd.parse(bytes)
    local model = parsed and parsed.models and parsed.models[1]
    local packed = model and Pack.pack(model)
    if packed then
      local at = bytes:find("TEX0", 1, true)
      local tex = at and Models.parse(bytes, at - 1)
      local written = {}
      for _, shape in ipairs(packed.shapes) do
        local tname = shape.texture
        if tname and tex then
          if written[tname] == nil then
            written[tname] = false
            local index, palette
            for k, t in ipairs(tex.textures) do if t.name == tname then index = k end end
            for k, pl in ipairs(tex.palettes or {}) do if pl.name == shape.palette then palette = k end end
            local image = index and Models.decode(tex, bytes, index, palette or 1)
            local saved = image and saveImage(("hgss_bag/%s_%s"):format(who, tname:gsub("[^%w_%-]", "_")), image)
            written[tname] = saved and saved.path or false
          end
          shape.image = written[tname] or nil
        end
      end
      -- THE POCKET LIGHTS UP: BTP0 57 + p (boy) / 76 + p (girl) puts material
      -- `kaban<p+1>` -- that pocket of the bag -- in texture `?_kaban.2` and
      -- its own palette, every other pocket staying in `.1`
      if tex then
        local litName = (who == "m" and "m" or "f") .. "_kaban.2"
        local index, palette
        for k, t in ipairs(tex.textures) do if t.name == litName then index = k end end
        for k, pl in ipairs(tex.palettes or {}) do if pl.name == litName .. "_pl" then palette = k end end
        local image = index and Models.decode(tex, bytes, index, palette or 1)
        local saved = image and saveImage(("hgss_bag/%s_lit"):format(who), image)
        packed.litImage = saved and saved.path or nil
        packed.litMaterial = "kaban%d"
      end
      packed.pockets = {}
      for p = 0, 7 do
        local abytes = m(A.POCKET_ANIM[who] + p)
        local pa = abytes and Anim.parse(abytes)
        local an = pa and pa.animations and pa.animations[1]
        local tracks = an and Anim.jointMatrices(abytes, an)
        if tracks then
          local list = {}
          for _, joint in ipairs(tracks) do
            list[#list + 1] = { index = joint.index, frames = joint.frames, matrices = Anim.packTrack(joint.track) }
          end
          packed.pockets[p + 1] = { frames = an.frames, tracks = list }
        end
      end
      out[who] = packed
    end
  end
  return out
end

return A
