-- choose_starter_app.c loadBgGraphics: the preview's two sub BG layers.
local A={}
function A.images(rom)
 local G=require('src.import.Gen4Graphics')
 local arc=assert(require('src.import.NarcArchive').parse(rom:read('/a/0/8/2')))
 local function m(i)local b=arc:get(i);return G.isCompressed(b) and G.decompress(b) or b end
 local out={}
 for _,r in ipairs({{'preview',11,10,9},{'preview_overlay',17,16,15}}) do
  local map=assert(G.tilemap(m(r[2])))
  for _,cell in ipairs(map.cells) do cell.palette=0 end
  -- palette() also returns a VRAM size. Passing it as the last argument
  -- forwarded that number as compose's firstTile, shifting every tile.
  local palette=assert(G.palette(m(r[4])))
  out[r[1]]=assert(G.compose(map,G.tiles(m(r[3])),palette))
 end
 return out
end
function A.build(x)
 local out={}
 for key,image in pairs(A.images(x.rom)) do out[key]=x:saveImage('hgss_starter/'..key,image) end
 return out
end
return A
