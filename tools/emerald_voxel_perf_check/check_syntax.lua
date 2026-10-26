local files={'main.lua','lib/BuildBudget.lua','lib/Buildings.lua','lib/ChunkMesher.lua','lib/Gen3.lua','lib/EmeraldBuildings.lua','lib/MeshBatch.lua','lib/MeshBounds.lua','lib/ShadowMap.lua','lib/Structures.lua','lib/Voxel3D.lua','lib/VoxelDiskCache.lua','lib/Water.lua','lib/VoxelScene.lua','lib/AnalysisCache.lua','lib/StampStream.lua','lib/HullBatch.lua','lib/ShaderState.lua','lib/EngineSheets.lua','lib/Rewrap.lua','lib/RetireQueue.lua','lib/GraphicsCompat.lua','lib/GpuMesher.lua','lib/GpuQuadSink.lua','lib/TilePlotCache.lua','lib/HullCache.lua','lib/AtlasPixels.lua','lib/QuadIndices.lua','lib/EnginePixelCanvas.lua'}
files[#files+1]='lib/HullPoints.lua'
files[#files+1]='lib/RenderStamp.lua'
files[#files+1]='lib/AtlasUpdates.lua'
files[#files+1]='lib/TerrainAtlas.lua'
for _,file in ipairs(files) do assert(loadfile('mods/DRAMATIC_SHAPE/'..file),file) end
for _,file in ipairs({'main.lua','conf.lua','src/render/ClipSpaceCompat.lua','src/render/Gen4Model.lua','src/render/Gen4Ground.lua','src/update/Boot.lua','src/render/TileRenderer.lua','src/render/Gen3Tiles.lua'})do assert(loadfile(file),file)end
print('Voxel Lua syntax: '..#files..' mod files and 8 host files passed')
