-- BW's live main-menu frames come from the shared /a/0/3/5 window bundle,
-- not the unused editor layouts in /a/0/2/7. Verified against native BG maps.
local A={PATH='/a/0/3/5',BANK=179}
function A.images(rom,version)
  local G=require('src.import.Gen4Graphics')
  local Lz=require('src.import.Gen5Lz')
  local arc=assert(require('src.import.NarcArchive').parse(assert(rom:read(A.PATH))))
  local function m(i)
    local b=assert(arc:get(i))
    return Lz.isCompressed(b) and assert(Lz.decompress(b)) or b
  end
  local sheet=assert(G.tiles(m(3)))
  local palette=assert(G.palette(m(4)))
  local out={}
  local bg=assert(G.tilemap(m(2)))
  if version=='white' then for _,cell in ipairs(bg.cells) do cell.palette=4 end end
  out.background=assert(G.compose(bg,sheet,palette))
  local small=assert(G.tilemap(m(7)))
  local large=assert(G.tilemap(m(6)))
  for _,state in ipairs({{'idle',1},{'focus_low',2},{'focus_high',3}}) do
    for _,size in ipairs({'small','large'}) do
      local source=size=='small' and small or large
      local cells={};local cols=source.width/8
      local width=size=='small' and 24 or cols
      for y=0,source.height/8-1 do for x=0,width-1 do
        -- The small resource has a transparent tile on either side. The
        -- native application copies its central 24 tiles to (4,2).
        local c=source.cells[y*cols+x+(size=='small' and 2 or 1)]
        cells[#cells+1]={tile=c.tile,flipX=c.flipX,flipY=c.flipY,
          palette=c.palette==1 and state[2] or c.palette}
      end end
      out[size..'_'..state[1]]=assert(G.compose({width=width*8,height=source.height,cells=cells},sheet,palette))
    end
  end
  return out,{text=palette[82],shadow=palette[83]} -- shared palette 5, roles 1/2
end
function A.build(x)
  local out={source='ROM:/a/0/3/5 (background 2/3/4, frames 6/7, palette 1/2/3)',text={}}
  for i=0,35 do out.text[i]=x:string(A.BANK,i) end
  local images,ink=A.images(x.rom,x.version)
  out.ink=ink
  for key,pic in pairs(images) do out[key]=assert(x:saveImage('bw_main_menu/'..key,pic)) end
  return out
end
return A
