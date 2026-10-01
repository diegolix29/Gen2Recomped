-- Resources whose runtime indices are shared across species or wallpapers.
local G=require('src.import.Gen4Graphics')
local N=require('src.import.NarcArchive')
local C=require('src.import.Gen4Cells')
local Anim=require('src.import.Gen4CellAnim')
local R={}
function R.images(rom)
 local out={}
 local function archive(path) local b=rom:read(path);return b and N.parse(b) end
 local function member(a,i)
  local b=a and a:get(i);if b and G.isCompressed(b) then b=G.decompress(b) end;return b
 end
 local function picture(a,tiles,map,pal)
  local sheet=G.tiles(member(a,tiles));local tilemap=G.tilemap(member(a,map));local palette=G.palette(member(a,pal))
  if not (sheet and tilemap and palette) then return nil end
  local slot=tilemap.cells[1] and tilemap.cells[1].palette or 0
  if #palette<=16 and slot>0 then palette=G.paletteAtSlot(palette,slot) end
  return G.compose(tilemap,sheet,palette)
 end
 local opening=archive('/demo/title/op_demo.narc')
 if opening then
  out['opening/first_top']=picture(opening,16,17,15)
  out['opening/first_bottom']=picture(opening,16,18,15)
  out['opening/first_overlay']=picture(opening,114,113,115)
 end
 for key,pic in pairs(require('src.import.Gen4OpeningAssets').images(rom)) do out[key]=pic end
 local box=archive('/graphic/box.narc')
 local shop=archive('/graphic/shop_gra.narc')
 if shop then
  local palette=G.palette(member(shop,10))
  for _,resource in ipairs({{name='cursor',tiles=7,cells=8,anim=9},{name='scroll',tiles=4,cells=5,anim=6}}) do
   local sheet=G.tiles(member(shop,resource.tiles));local bank=C.parse(member(shop,resource.cells),G)
   local anim=Anim.parse(member(shop,resource.anim),G)
   if palette and sheet and bank and anim then
    for sequence=0,#anim.sequences-1 do
     local frames=Anim.frames(anim,sequence);local cell=frames and frames[1] and bank.cells[frames[1].cell+1]
     if cell then
      local pic=C.assemble(cell,sheet,palette,bank,G)
      if pic then pic.originX,pic.originY=C.extent(cell);out[('shop/%s_%02d'):format(resource.name,sequence)]=pic end
     end
    end
   end
  end
 end
 if box then
  out['storage/main']=picture(box,1,0,5)
  -- ov19_021D8B54: cursor NCGR/NCER/NANR 12/13/14, shared OBJ palette 26.
  local sheet=G.tiles(member(box,12));local bank=C.parse(member(box,13),G)
  local palette=G.palette(member(box,26));local animation=Anim.parse(member(box,14),G)
  if sheet and bank and palette and animation then
   for sequence=0,9 do
    local frames=Anim.frames(animation,sequence)
    local cellId=frames and frames[1] and frames[1].cell
    local cell=cellId and bank.cells[cellId+1]
    if cell then
     local pic=C.assemble(cell,sheet,palette,bank,G)
     if pic then pic.originX,pic.originY=C.extent(cell);out[('storage/cursor_%02d'):format(sequence)]=pic end
    end
   end
  end
  for i=0,31 do out[('storage/wallpaper_%02d'):format(i)]=picture(box,29+i*3,30+i*3,28+i*3) end
 end
 local egg=archive('/demo/egg/data/egg_data.narc')
 if egg then out['evolution/background']=picture(egg,0,1,8) end
 local dexPath=require('src.import.Gen4Dex').PATH
 local dex=archive(dexPath)
 if dex then
  local A=require('src.import.Gen4Archives')
  local function named(tiles,map,pal) return picture(dex,A.find(dexPath,tiles..'.NCGR.lz'),A.find(dexPath,map..'.NSCR.lz'),A.find(dexPath,pal..'.NCLR')) end
  out['pokedex/area_map']=named('entry_main','area_map','banner_sinnoh')
  out['pokedex/cry_button']=named('entry_main','cry_button','banner_sinnoh')
  out['pokedex/height_check_main']=named('entry_main','height_check_main','banner_sinnoh')
  out['pokedex/weight_check_main']=named('entry_main','weight_check_main','banner_sinnoh')
  out['pokedex/cry_sub']=named('entry_sub','cry_sub','cry_sub')
  out['pokedex/forms_sub']=named('entry_sub','forms_sub','background_sub_2')
 end
 local foot=archive('/poketool/pokefoot/pokefoot.narc')
 if foot then
  local palette=G.palette(member(foot,0));local bank=C.parse(member(foot,2),G)
  if palette and bank then
   palette=Anim.paletteFor(palette,Anim.bankOf(bank) or 0)
   for species=1,493 do
    local sheet=G.tiles(member(foot,3+species))
    if sheet then out[('dex/footprint_%03d'):format(species)]=C.assemble(bank.cells[1],sheet,palette,bank,G) end
   end
  end
 end
 return out
end
return R
