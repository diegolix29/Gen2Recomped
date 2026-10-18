-- Exercise the real BW constructor through the production import worker,
-- without extracting or changing an installed cache.
local F={}
function F.new(path,version,manifest,progress)
 assert(type(path)=='string' and #path<4096,'DS worker must pass a filename, not ROM bytes')
 local x,why=require('src.import.RomExtractorGen5').new(path,version,manifest,progress)
 assert(x,why)
 function x:run()
  assert(self:string(44,6):find('Welcome to the world',1,true),'BW NARC text must be readable through worker path')
 end
 return x
end
return F
