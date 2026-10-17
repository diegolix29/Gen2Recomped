-- HGSS Pokegear backgrounds from the loaders in application/pokegear.
local G = require("src.import.Gen4Graphics")
local N = require("src.import.NarcArchive")
local A = {}
local function archive(rom, path)
  local arc = assert(N.parse(assert(rom:read(path))))
  return function(i)
    local b = arc:get(i)
    return b and (G.isCompressed(b) and G.decompress(b) or b)
  end
end
local function crop(img)
  if not img then return nil end
  local rows = {}
  for y=0,191 do
    local row = y < img.height and img.rgba:sub(y*img.width*4+1,(y*img.width+math.min(256,img.width))*4) or ''
    rows[#rows+1] = row .. string.rep('\0',256*4-#row)
  end
  return {width=256,height=192,rgba=table.concat(rows)}
end
local function compose(m, map, char, palette, bpp, softwareMap)
  local sheet = assert(G.tiles(m(char)))
  if bpp then sheet.bpp=bpp;sheet.perTile=bpp==8 and 64 or 32 end
  local tilemap = assert(G.tilemap(m(map)))
  if softwareMap then
    -- ov101_021EAF40 copies from a linear 64-column source into hardware BG
    -- memory. The source NSCR is not already laid out in 32x32 DS blocks.
    local cells={}
    for y=0,23 do for x=0,31 do
      cells[#cells+1]=tilemap.cells[y*64+x+1] or {tile=0,palette=0}
    end end
    tilemap={width=256,height=192,cells=cells}
  end
  return crop(G.compose(tilemap,sheet,palette))
end
function A.images(rom)
  local core = archive(rom,"/a/1/4/3")
  local phone = archive(rom,"/a/1/4/6")
  local map = archive(rom,"/a/1/4/4")
  local radio = archive(rom,"/a/1/4/7")
  local config = archive(rom,"/a/1/4/5")
  local out={}
  for skin=0,5 do
    local function palette(page, member, sub)
      local pal=G.palette(page(member+skin))
      local casing=G.palette(core((sub and 24 or 30)+skin))
      -- Main casing occupies slots 14-15; sub casing slots 12-15.
      local offset=sub and 192 or 224
      for i=offset+1,256 do pal[i]=casing[i] or pal[i] end
      return pal
    end
    local top = palette(phone,10,false)
    local bottom = palette(phone,4,true)
    -- The main-frame NSCR is a button atlas: only four rows are copied to
    -- y=160 on screen (PokegearApp_DrawAppButtons), not displayed at y=0.
    local source = assert(G.tilemap(core(54+skin)))
    local cells={}
    for y=0,23 do for x=0,31 do
      cells[#cells+1]=y>=20 and source.cells[(y-20)*32+x+1] or {tile=0,palette=0}
    end end
    out['frame_top_'..skin]=crop(G.compose({width=256,height=192,cells=cells},G.tiles(core(48+skin)),top))
    out['frame_bottom_'..skin]=compose(core,42+skin,36+skin,bottom)
    out['phone_top_'..skin]=compose(phone,34+skin,28+skin,top)
    out['phone_bottom_'..skin]=compose(phone,22+skin,16+skin,bottom)
    out['map_top_'..skin]=compose(map,32+skin,26+skin,palette(map,20,false))
    out['map_bottom_'..skin]=compose(map,56+skin,50+skin,palette(map,14,true))
    out['map_world_'..skin]=compose(map,11,10,palette(map,20,false),8,true)
    out['radio_top_'..skin]=compose(radio,22+skin,16+skin,palette(radio,10,false))
    out['radio_bottom_'..skin]=compose(radio,40+skin,34+skin,palette(radio,4,true))
    out['config_top_'..skin]=compose(config,16+skin,10+skin,palette(config,4,false))
  end
  return out
end
function A.build(x)
  local out={}
  for name,img in pairs(A.images(x.rom)) do out[name]=x:saveImage('hgss_pokegear/'..name,img) end
  -- phonebook_dat.c sPhoneMessageGmm, found by its first six bank IDs.
  local arm9=x.rom:arm9()
  local anchor=string.char(152,2,204,2,154,2,150,2,151,2,131,2)
  local at=arm9:find(anchor,1,true)
  assert(at and not arm9:find(anchor,at+1,true),'HGSS phone-message table is not unique')
  out.contacts={}
  for id=0,74 do
    local lo,hi=arm9:byte(at+id*2,at+id*2+1)
    local bank=lo+hi*256
    out.contacts[id]={bank=bank,name=x:string(bank,0)}
  end
  return out
end
return A
