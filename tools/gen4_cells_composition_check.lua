local C=require('src.import.Gen4Cells')
local G=require('src.import.Gen4Graphics')
local palette={{0,0,0},{255,0,0},{0,255,0}}
local sheet={bpp=4,perTile=32,count=3,pixels=string.rep('\17',32)..'\2'..string.rep('\0',31)..string.rep('\34',32)}
local cell={oam={{x=3,y=2,width=8,height=8,tile=1,palette=0},{x=0,y=0,width=8,height=8,tile=0,palette=0}}}
local pic=assert(C.assemble(cell,sheet,palette,{boundary=32},G))
assert(pic.width==11 and pic.height==10,'pixel offsets must preserve the exact extent')
local function pixel(x,y) local at=(y*pic.width+x)*4+1;return pic.rgba:sub(at,at+3) end
assert(pixel(3,2)=='\0\255\0\255','earlier OAM entry must cover the lower entry')
assert(pixel(4,2)=='\255\0\0\255','transparent upper pixels must reveal lower OAM')
assert(pixel(10,9)=='\0\0\0\0','empty margins must stay transparent')
local moved={oam={{x=0,y=0,width=8,height=8,tile=0,palette=0}},transfer={offset=64,size=32}}
local shifted=assert(C.assemble(moved,sheet,palette,{boundary=32},G))
assert(shifted.rgba:sub(1,4)=='\0\255\0\255','per-cell character transfer must select the right pixels')
print('OBJ composition: pixel offsets, overlap priority, transparency and character transfers passed')

