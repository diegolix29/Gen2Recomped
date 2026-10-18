-- BLACK AND WHITE'S BATTLE INTERFACE (/a/0/1/1), for src/battle/Gen5BattleHud.lua.
--
-- What each member is was settled by decoding and looking (scratch_claude/
-- bw_ui_map.md; the cartridge's file table carries no names):
--
--   165-167 / 168-170   the foe's / the player's healthbox (NCGR, NCER, NANR):
--                        one cell, two 64x32 OAMs from (-64, -16) -- a bar with
--                        "HP" and "Lv" on it and, on the player's, the dark
--                        strip under it for the numbers and the EXP line
--   163                  their palette (row 0)
--   164                  the gauge parts, 32 x 2 tiles: row 0 the HP fills
--                        (green 0-8, yellow 9-17, red 18-26, a tile per
--                        pixel step), the caught ball (27), the gender signs;
--                        row 1 the EXP fill (0-8), the digits 0-9 (9-18), "Lv"
--   189-192              the party ball gauge (cells 0-24 ball states, 25 / 26
--                        the gauge's two bars) on palette 190
--   91 / 92 / 93-111     the touch screen: tileset, palette, and 512 x 512
--                        maps holding four 256-pixel screens each -- 104's
--                        first is the FIGHT! screen (and its fourth the four
--                        move buttons), 93's first the BAG / RUN / POKeMON row
--                        and its second the back button
--   193-211              one-row palettes recolouring a move button by type

local U = {}

U.PATH = "/a/0/1/1"
U.MOVE_RECTS={{x=2,y=30,w=124,h=50},{x=130,y=30,w=124,h=50},
 {x=2,y=82,w=124,h=50},{x=130,y=82,w=124,h=50}}
-- Overlay 94's u32 table (Black file offset 0x14090). Its order is the
-- personal/move type enum, not the palette archive order or colour guesses.
function U.typeMembers(rom)
 local expected={194,200,203,201,202,206,205,207,209,195,196,198,197,199,208,204,210}
 local parts={};for _,n in ipairs(expected)do parts[#parts+1]=string.char(n,0,0,0)end
 local signature=table.concat(parts)
 for overlay=94,94 do
  local data=rom:overlay(overlay)
  local at=data and data:find(signature,1,true)
  if at then
   local out={}
   for id,key in pairs(require("src.import.Gen5Data").TYPES)do out[key]=data:byte(at+id*4)end
   return out,{overlay=overlay,offset=at-1}
  end
 end
 return nil,"BW move palette table not found"
end

-- the touch screen's pieces: { name, map, x, y } -- the 256 x 192 window of
-- the 512 x 512 map the screen scrolls to (moves: the right half, 192 down)
U.LAYERS = {
  { name = "base", map = 104, x = 0, y = 0 },
  { name = "action", map = 93, x = 0, y = 0 },
  { name = "moves", map = 104, x = 256, y = 192 },
  { name = "moves_alt", map = 104, x = 256, y = 256 },
  { name = "back", map = 93, x = 256, y = 0 },
}

function U.build(x)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local raw = x.rom:read(U.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return nil end
  local function m(i)
    local b = arc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local function row(pal, r)
    local o = {}
    for i = 1, 16 do o[i] = pal[r * 16 + i] or { 0, 0, 0 } end
    return o
  end
  local out = { images = {} }
  local function save(name, image, extra)
    local entry = image and x:saveImage("battle5/" .. name, image, extra)
    if entry then out.images[name] = entry end
    return entry
  end

  -- the boxes
  local hpPal = G.palette(m(163))
  for _, set in ipairs({ { "healthbox_enemy", 165, 166 }, { "healthbox_player", 168, 169 },
                         { "healthbox_enemy_doubles", 171, 172 }, { "healthbox_player_doubles", 174, 175 } }) do
    local sheet = G.tiles(m(set[2]))
    local bank = Cells.parse(m(set[3]), G)
    local cell = bank and bank.cells[1]
    local pic = cell and hpPal and Cells.assemble(cell, sheet, row(hpPal, 0), bank, G)
    if pic then
      local ox, oy = Cells.extent(cell)
      save(set[1], pic, { originX = ox, originY = oy })
    end
  end
  -- the gauge parts, as one 256 x 16 strip
  do
    local sheet = G.tiles(m(164))
    if sheet and hpPal then
      local cells = {}
      for t = 0, sheet.count - 1 do cells[t + 1] = { tile = t, palette = 0 } end
      save("gauge_parts", G.compose({ width = 256, height = 16, cells = cells }, sheet, row(hpPal, 0)),
           { tile = 8, hp = { green = 0, yellow = 9, red = 18 }, exp = 32, digit0 = 41, lv = 52,
             ball = 27, male = 28, female = 30 })
    end
  end
  -- the party balls
  do
    local sheet = G.tiles(m(189))
    local pal = G.palette(m(190))
    local bank = Cells.parse(m(191), G)
    if sheet and pal and bank then
      for c = 1, #bank.cells do
        local cell = bank.cells[c]
        local pic = Cells.assemble(cell, sheet, row(pal, cell.oam[1] and cell.oam[1].palette or 0), bank, G)
        if pic then
          local ox, oy = Cells.extent(cell)
          save(("ball_%02d"):format(c - 1), pic, { originX = ox, originY = oy })
        end
      end
    end
  end
  -- the touch screen
  do
    local sheet = G.tiles(m(91))
    local pal = G.palette(m(92))
    local maps = {}
    for _, layer in ipairs(U.LAYERS) do
      local map = maps[layer.map]
      if map == nil then
        map = G.tilemap(m(layer.map)) or false
        maps[layer.map] = map
      end
      local full = map and sheet and pal and G.compose(map, sheet, pal)
      if full then
        local qx, qy = layer.x, layer.y
        local w, h = 256, 192
        local rgba = {}
        for y = 0, h - 1 do
          local from = ((qy + y) * full.width + qx) * 4
          rgba[#rgba + 1] = full.rgba:sub(from + 1, from + w * 4)
        end
        save("sub_" .. layer.name, { width = w, height = h, rgba = table.concat(rgba) })
      end
    end
    -- the move buttons' type colours: palette rows to swap into the button
    local types = {}
    for i = 193, 211 do
      local p = G.palette(m(i))
      if p then
        local r0 = {}
        for k = 1, 16 do local c = p[k] or { 0, 0, 0 } r0[k] = { c[1], c[2], c[3] } end
        types[#types + 1] = r0
      end
    end
    out.typePalettes = types
    local members,location=U.typeMembers(x.rom)
    out.typeMembers=members;out.typePaletteTable=location
    local map=maps[104]
    if members and map and sheet and pal then
      for key,member in pairs(members)do
        local typePalette=G.palette(m(member))
        if typePalette then
          local recoloured={};for i,c in pairs(pal)do recoloured[i]=c end
          for slot=9,12 do for i=1,16 do recoloured[slot*16+i]=typePalette[i]end end
          local full=G.compose(map,sheet,recoloured)
          for i,rect in ipairs(U.MOVE_RECTS)do
            local rgba={}
            for y=0,rect.h-1 do
              local at=((192+rect.y+y)*full.width+256+rect.x)*4
              rgba[#rgba+1]=full.rgba:sub(at+1,at+rect.w*4)
            end
            save("move_"..key.."_"..i,{width=rect.w,height=rect.h,rgba=table.concat(rgba)})
          end
        end
      end
    end
  end
  out.source = "ROM:/a/0/1/1 (healthboxes 165-176, parts 164 / palette 163, balls 189-192, touch screen 91 / 92 / 93-111)"
  return out
end

return U
