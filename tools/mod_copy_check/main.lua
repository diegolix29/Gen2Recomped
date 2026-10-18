do
  local root = (os.getenv("ROOT") or love.filesystem.getWorkingDirectory()):gsub("\\", "/")
  local ffi = require("ffi")
  pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
  for _, lib in ipairs({ function() return ffi.C end, function() return ffi.load("love") end }) do
    local ok, l = pcall(lib)
    if ok and l then
      local okf, fn = pcall(function() return l.PHYSFS_mount end)
      if okf and fn and fn(root, "", 1) ~= 0 then break end
    end
  end
end

local count=0
local function check(v,why) assert(v,why);count=count+1 end
local importer
function love.load()
 local LM=require('src.mods.LauncherMods')
 local fs=love.filesystem
 local root=assert(os.getenv('ROOT'))..'/tmp/mod_copy_check/'
 local base='test_dramatic_shapes'
 for i=0,2 do
  local ok,id=LM.installZip(root..'original.zip')
  check(ok and id==base..(i==0 and '' or '-'..i),'numbered import '..i..': '..tostring(id))
 end
 local Json=require('src.link.Json')
 check(Json.decode(fs.read('mods/'..base..'-1/manifest.json')).id==base..'-1','persisted independent manifest id')
 local options=require('src.core.SaveData').loadOptions()
 check(options.mods[base..'-1']==false and options.mods[base..'-2']==false,'new renderers start disabled')
 local rows={};for _,m in ipairs(LM.list()) do rows[m.id]=m end
 for i=0,2 do check(rows[base..(i==0 and '' or '-'..i)],'separate launcher row '..i) end
 local Loader=require('src.mods.Loader')
 local loader=Loader.new({});loader:_discover()
 for i=0,2 do check(loader.mods[base..(i==0 and '' or '-'..i)],'separate loader identity '..i) end
 -- Exercise the public release update entry point without any network.
 package.loaded['src.mods.ModUpdate']={downloadZip=function() return root..'updated.zip' end}
 local ok,version=LM.installFromRelease(base..'-1',{version='2.0.0',zip={url='fixture'}})
 check(ok and version=='2.0.0','update selected numbered copy: '..tostring(version))
 check(fs.read('mods/'..base..'-1/marker.txt')=='updated','selected copy updated')
 check(fs.read('mods/'..base..'/marker.txt')=='original' and fs.read('mods/'..base..'-2/marker.txt')=='original','other copies preserved')
 check(require('src.core.SaveData').loadOptions().mods[base..'-1']==false,'update preserves disabled flag')
 ok=LM.installZip(root..'wrong.zip',{replace=true,expectId=base,installId=base..'-1'})
 check(not ok and fs.read('mods/'..base..'-1/marker.txt')=='updated','wrong mod update refused')
 ok=LM.installZip(root..'updated.zip',{replace=true})
 check(ok and fs.read('mods/'..base..'/marker.txt')=='updated','explicit base replacement works')
 check(fs.read('mods/'..base..'-2/marker.txt')=='original','base replacement leaves copy alone')
 ok=LM.uninstall(base..'-1');check(ok,'delete one copy')
 check(not LM.folderFor(base..'-1') and LM.folderFor(base) and LM.folderFor(base..'-2'),'delete preserves siblings')
 ok,version=LM.installZip(root..'original.zip');check(ok and version==base..'-1','reuse free numbered slot')
 local batch=LM.installMany({root..'original.zip',root..'original.zip'})
 check(#batch.installed==2 and #batch.skipped==0 and #batch.failed==0,'mass import keeps repeated copies')
 check(LM.folderFor(base..'-3') and LM.folderFor(base..'-4'),'batch copies numbered independently')
 -- Keep the screenshot focused on the first three copies.
 check(LM.uninstall(base..'-3') and LM.uninstall(base..'-4'),'delete extra batch copies independently')
 local RI=require('src.import.RomImporter')
 importer=RI.new(function() end,{launcher=true});importer:_sbGo('mods')
 print('Mod copy checks: '..count..' passed')
end
local frames=0
function love.update()
 importer:update(1/60);frames=frames+1
 if frames==3 then love.graphics.captureScreenshot(function(img)
  local file=assert(io.open(assert(os.getenv('OUT')),'wb'));file:write(img:encode('png'):getString());file:close();love.event.quit()
 end) end
end
function love.draw() importer:draw() end
