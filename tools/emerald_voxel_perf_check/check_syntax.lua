local root='mods/DRAMATIC_SHAPE/'
for _,file in ipairs({'main.lua','lib/BuildBudget.lua','lib/Buildings.lua','lib/ChunkMesher.lua','lib/Gen3.lua','lib/EmeraldBuildings.lua','lib/MeshBatch.lua','lib/MeshBounds.lua','lib/ShadowMap.lua','lib/Structures.lua','lib/Voxel3D.lua','lib/VoxelDiskCache.lua','lib/Water.lua','lib/VoxelScene.lua','lib/AnalysisCache.lua','lib/StampStream.lua','lib/HullBatch.lua','lib/ShaderState.lua','lib/EngineSheets.lua','lib/Rewrap.lua','lib/RetireQueue.lua'}) do
 assert(loadfile(root..file),file)
end
print('Voxel Lua syntax: 21 files passed')
