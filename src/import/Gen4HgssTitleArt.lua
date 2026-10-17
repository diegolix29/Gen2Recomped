-- title_screen.c TitleScreenAnim_Load2dBgGfx, numbered title archive.
local A={PATH='/a/0/4/6'}
function A.images(rom)
  local G=require('src.import.Gen4Graphics')
  local arc=assert(require('src.import.NarcArchive').parse(rom:read(A.PATH)))
  local function m(i) local b=arc:get(i);return G.isCompressed(b) and G.decompress(b) or b end
  local out={}
  for _,who in ipairs({'heartgold','soulsilver'}) do
    local hg=who=='heartgold'
    local pal=assert(G.palette(m(hg and 4 or 2)))
    local function put(key,map,char)
      out[who..'_'..key]=assert(G.compose(G.tilemap(m(map)),G.tiles(m(char)),pal))
    end
    put('logo',0,hg and 3 or 1)
    put('background',hg and 35 or 37,hg and 34 or 36)
    put('copyright',17,15)
  end
  return out
end
function A.build(x)
  local out={prompt=x:string(719,0)}
  for key,pic in pairs(A.images(x.rom)) do out[key]=x:saveImage('hgss_title/'..key,pic) end
  return out
end
return A
