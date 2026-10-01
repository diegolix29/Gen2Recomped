package.path='tools/save-editor/?.lua;'..package.path
local Edits=require('tools.map-editor.MapEdits')
local def={width=2,height=1,blocks=string.char(5,240,6,160)}
require('src.world.Map').blockArray(def)
assert(Edits.writePackedBlock(def,0,0,777))
assert(def.blocks:byte(2)==243 and require('src.world.Map').blockArray(def)[1]==777)
local S={version='platinum',mapId='T01',data={maps={T01={id='T01',generation=4,width=32,height=32}}},mapEdits={games={}}}
local list={{model=12,x=16,y=8,z=32,scaleX=1.5,scaleY=2,scaleZ=1}}
require('tools.map-editor.panels.Models').commit(S,0,list)
assert(S.mapEditsDirty and S.mapEdits.games.platinum.maps.T01.map.gen4ModelEdits['0'][1].model==12)
local reloaded={id='T01',width=32,height=32,objects={}}
Edits.applyToMap(S.mapEdits,'platinum','T01',reloaded)
assert(reloaded.gen4ModelEdits['0'][1].scaleY==2)
local ground=setmetatable({def=reloaded,signpostsFor=function() return {} end},require('src.render.Gen4Ground'))
assert(ground:objectsFor(0,{objects={{model=99}}})[1].model==12)
local Catalog=require('Catalog')
assert(Catalog.mapLabel({maps={T01={label='Twinleaf Town'}}},'T01')=='Twinleaf Town')
print('Packed terrain flags, model overlay persistence/runtime rendering and Platinum town labels passed')
