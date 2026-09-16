local mod=...
local VERSION="2.0.1"
mod.exports.version=VERSION
mod.exports.releaseBuild="cbe-2.0.1"

local function package(path,arg)
  local src=mod:read(path)
  if not src then error("COLOSSEUM_BATTLE_ENVIRONMENTS: missing "..path,0) end
  local chunk,err=load(src,"@"..tostring(mod.path or mod.id).."/"..path)
  if not chunk then error(err,0) end
  return chunk(arg)
end

-- Gen1Recomp owns required-import selection and validation. Native
-- mod.imports/mod.cache provide bounded source access and an installation-scoped
-- generated cache. The compatibility bridge never receives the original host path.
local NativeLauncherCompat=package("lib/NativeLauncherCompat.lua")
local launcherCompat=NativeLauncherCompat.install(mod)
local BuildProgressUI=package("lib/BuildProgressUI.lua")
local AudioFidelity=package("lib/AudioFidelity.lua")
local GeneratedCacheReset=package("lib/GeneratedCacheReset.lua")

local function platformOS()
  if love and love.system and type(love.system.getOS)=="function" then
    local ok,v=pcall(love.system.getOS);if ok and v then return tostring(v) end
  end
  return "Unknown"
end
local PLATFORM_OS=platformOS()
local IS_ANDROID=PLATFORM_OS=="Android"

-- Build the user-owned Colosseum source into an installation-scoped runtime
-- before any battle provider is allowed to acquire generated content.
local extractionStatus={state="NOT RUN",visualReady=false,audioReady=false,message=nil}
local sourceImported=false
local cacheGateOutcome=nil
local startupCachePolicyResolved=false
local startupExitRequested=false

-- Captured during runBuild so the Colosseum Pokemon actor service can build a
-- species on first send-out. The closure keeps the host path private: the
-- runtime gains the ability to ASK for an opened disc, never the path itself.
local openColosseumDisc=nil
local PokemonExtractorRef=nil
local PKXMetadataRef=nil
local MoveFXExtractorRef=nil
local BuildPipelineRef=nil
local ColosseumPokemonMoveDataRef=nil
local ColosseumUIFontSourceRef=nil

-- Pokemon model extraction stays lazy after the arena bootstrap. Keep the
-- launcher-owned source capability alive for CBE's lifetime so any uncached
-- species can be built on first use; there is no valid post-bootstrap release
-- boundary. The mod never receives the original host path.
local function runBuild(requestedBuildOptions)
  ColosseumPokemonMoveDataRef=nil
  ColosseumUIFontSourceRef=nil
  if not (mod.imports and mod.cache) then
    extractionStatus={state="HOST API MISSING",visualReady=false,audioReady=false,message="Colosseum Battle Environments requires Gen1Recomp required-import support with mod.imports/mod.cache."}
    return
  end
  local info,infoErr=mod.imports:info("pokemon_colosseum_usa")
  sourceImported=info~=nil
  if not info then
    extractionStatus={state="ROM NOT IMPORTED",visualReady=false,audioReady=false,message="In the Gen1Recomp launcher, open MODS > Colosseum Battle Environments > IMPORT FILE.., select your Pokemon Colosseum USA GC6E01 disc image (raw ISO/GCM or GameCube CISO; the selected filename/extension does not matter once the launcher can validate it), then launch the game with CBE enabled. Current Gen1Recomp builds retain this source across CBE updates."}
    return
  end
  local GXTexture=package("extract/GXTexture.lua")
  local GameCubeDisc=package("extract/GameCubeDisc.lua")
  local FSYS=package("extract/FSYS.lua")
  local HSD=package("extract/HSD.lua",{GXTexture=GXTexture})
  local PayloadPreserver=package("extract/PayloadPreserver.lua")
  local ArenaBuilder=package("extract/ArenaBuilder.lua",{HSD=HSD,FSYS=FSYS,
    ArenaAudienceProfile=package("lib/ArenaAudienceProfile.lua"),ArenaCacheIdentity=package("lib/ArenaCacheIdentity.lua"),PayloadPreserver=PayloadPreserver})
  local TransitionBuilder=package("extract/TransitionBuilder.lua",{PayloadPreserver=PayloadPreserver})
  local PortableMusyX=package("extract/PortableMusyX.lua")
  local AudioProbe=package("extract/AudioProbe.lua",{FSYS=FSYS,PortableMusyX=PortableMusyX,AudioFidelity=AudioFidelity})
  local WazaSfxBuilder=package("extract/WazaSfxBuilder.lua",{FSYS=FSYS,PortableMusyX=PortableMusyX})
  local TrainerThrowSource=package("extract/TrainerThrowSource.lua")
  local TrainerExtractor=package("extract/TrainerExtractor.lua",{HSD=HSD,FSYS=FSYS,PayloadPreserver=PayloadPreserver,TrainerThrowSource=TrainerThrowSource})
  local ColosseumDex=package("lib/ColosseumDex.lua")
  local ShinySupport=package("lib/ShinySupport.lua")
  local PKXMetadata=package("extract/PKXMetadata.lua",{FSYS=FSYS,ColosseumDex=ColosseumDex,ShinySupport=ShinySupport})
  local PokemonExtractor=package("extract/PokemonExtractor.lua",{HSD=HSD,FSYS=FSYS,ColosseumDex=ColosseumDex,PKXMetadata=PKXMetadata,ShinySupport=ShinySupport,PayloadPreserver=PayloadPreserver})
  local WazaSequenceExtractor=package("extract/WazaSequenceExtractor.lua")
  local MoveFXExtractor=package("extract/MoveFXExtractor.lua",{FSYS=FSYS,GXTexture=GXTexture,HSD=HSD,WazaSequenceExtractor=WazaSequenceExtractor,PayloadPreserver=PayloadPreserver})
  local ColosseumSpeciesIndex=package("lib/ColosseumSpeciesIndex.lua")
  local ColosseumPokemonMoveData=package("extract/ColosseumPokemonMoveData.lua",{FSYS=FSYS,ColosseumSpeciesIndex=ColosseumSpeciesIndex})
  local ColosseumUIFont=package("extract/ColosseumUIFont.lua")
  local FormatProbe=package("extract/FormatProbe.lua",{FSYS=FSYS,HSD=HSD,WazaSequenceExtractor=WazaSequenceExtractor})
  local CameraProbe=package("extract/CameraProbe.lua",{FSYS=FSYS,HSD=HSD})
  PokemonExtractorRef=PokemonExtractor
  PKXMetadataRef=PKXMetadata
  MoveFXExtractorRef=MoveFXExtractor
  -- Hold only the validated FST index, never the full disc bytes. Re-opening
  -- the same installation import for every species/metadata request reparsed
  -- this immutable index repeatedly. A rebuild/reload creates a new closure.
  local residentDisc=nil
  openColosseumDisc=function()
    if residentDisc then return residentDisc end
    local disc,why=GameCubeDisc.open(mod)
    if disc then residentDisc=disc end
    return disc,why
  end
  local BuildPipeline=package("extract/BuildPipeline.lua",{
    GameCubeDisc=GameCubeDisc,FSYS=FSYS,GXTexture=GXTexture,HSD=HSD,
    ArenaBuilder=ArenaBuilder,TrainerExtractor=TrainerExtractor,
    TransitionBuilder=TransitionBuilder,AudioProbe=AudioProbe,WazaSfxBuilder=WazaSfxBuilder,
    PokemonExtractor=PokemonExtractor,MoveFXExtractor=MoveFXExtractor,FormatProbe=FormatProbe,CameraProbe=CameraProbe,ColosseumDex=ColosseumDex,
    LauncherCompat=launcherCompat,BuildVersion=VERSION,PlatformOS=PLATFORM_OS,GeneratedCacheReset=GeneratedCacheReset,
  })
  BuildPipelineRef=BuildPipeline
  local CueBuilder=package("extract/BattleAudioBuilder.lua",{FSYS=FSYS,PortableMusyX=PortableMusyX,
    BattleAudioSpec=package("lib/BattleAudioSpec.lua"),AudioFidelity=AudioFidelity})
  local FidelityBuilder=package("extract/AudioFidelityBuilder.lua",{FSYS=FSYS,PortableMusyX=PortableMusyX,
    AudioProbe=AudioProbe,BattleAudioSpec=package("lib/BattleAudioSpec.lua"),BattleAudioBuilder=CueBuilder,AudioFidelity=AudioFidelity,PayloadPreserver=PayloadPreserver})

  -- Existing generated cache policy belongs ahead of EVERY recovery/migration
  -- write. Recognizable cache state is always reused non-destructively: a fully
  -- current installation takes the verified zero-write startup path, while stale
  -- or partial recognized components flow into BuildPipeline's narrow incremental
  -- repair dispatcher. A release/version change is never a reason to ask the user
  -- to recache. Explicit REBUILD / WIPE remain separate cache-management actions.
  -- Detection is bounded and read-only (transaction markers/core payloads only).
  local buildOptions=type(requestedBuildOptions)=="table" and requestedBuildOptions or nil
  if not startupCachePolicyResolved then
    local hasExisting=BuildPipeline.hasGeneratedCache(mod)==true
    local safeReuse=hasExisting and BuildPipeline.canReuseWithoutPrompt and BuildPipeline.canReuseWithoutPrompt(mod)==true
    if safeReuse and not (buildOptions and buildOptions.forceRebuild==true) then
      startupCachePolicyResolved=true;cacheGateOutcome="auto-reuse"
      buildOptions=buildOptions or {};buildOptions.verifiedStartupReady=true
    elseif hasExisting then
      startupCachePolicyResolved=true;cacheGateOutcome="auto-repair"
    else
      startupCachePolicyResolved=true
    end
  end
  -- Recover interrupted pair/metadata writes before the normal cache gate can
  -- inspect or acquire any WAV. A failed recovery is not advertised as ready.
  FidelityBuilder.recover(mod)
  extractionStatus={state="RUNNING",visualReady=false,audioReady=false,message="Starting GC6E01 source build."}
  local okPipeline,result=pcall(BuildPipeline.run,mod,function(label,current,total)
    extractionStatus.state="RUNNING";extractionStatus.message=tostring(label);extractionStatus.current=current;extractionStatus.total=total
    BuildProgressUI.update(label,current,total)
    if mod.log and mod.log.info then pcall(mod.log.info,mod.log,"CBE source build: %s (%s/%s)",tostring(label),tostring(current or "?"),tostring(total or "?")) end
  end,buildOptions)
  if not okPipeline then error(result,0) end
  extractionStatus=result or extractionStatus
  -- MOVE PREP acquisition data is deliberately a tiny release-stable cache:
  -- all 386 PokemonStats rows plus the retail 58-entry TM/HM table. Reuse the
  -- compact cache across CBE releases and reopen/decompress common_rel only on
  -- a cache miss. A failure does not fabricate a partial catalog; runtime sees
  -- the explicit error and falls back to native Gen1/Gen2 data where possible.
  local okMoveData,moveData=pcall(ColosseumPokemonMoveData.load,mod,openColosseumDisc)
  if okMoveData then ColosseumPokemonMoveDataRef=moveData else
    ColosseumPokemonMoveDataRef={error=tostring(moveData),discId="GC6E01",source="GC6E01 MOVE PREP extraction failed"}
    if mod.log and mod.log.warn then pcall(mod.log.warn,mod.log,"CBE MOVE PREP source catalog unavailable: %s",tostring(moveData)) end
  end
  -- The retail UI font is another tiny acquisition cache. Its raw GC6E01
  -- main.dol bytes live at one release-stable cache path and are reused without
  -- reopening the source disc. Font failure is presentation-only: the UI keeps
  -- its existing fallback faces rather than blocking battle runtime startup.
  local okUIFont,fontData=pcall(ColosseumUIFont.load,mod,openColosseumDisc)
  if okUIFont and fontData then ColosseumUIFontSourceRef=fontData else
    ColosseumUIFontSourceRef={error=tostring(fontData),discId="GC6E01",source="GC6E01 UI font-0 extraction failed"}
    if mod.log and mod.log.warn then pcall(mod.log.warn,mod.log,"CBE retail Colosseum UI font unavailable: %s",tostring(fontData)) end
  end
  if extractionStatus.audioReady==true then
    local okCues,cues=pcall(CueBuilder.run,mod,openColosseumDisc,function(label,current,total)
      BuildProgressUI.update(label,current,total)
    end)
    extractionStatus.battleAudio=okCues and cues or {ready=false,error=tostring(cues)}
    if not(okCues and cues.ready) and mod.log and mod.log.warn then
      pcall(mod.log.warn,mod.log,"CBE battle cue preparation incomplete; unavailable cues retain native audio. Existing caches preserved.")
    end
  end
  if extractionStatus.audioReady==true and AudioFidelity.pending(mod) then
    local okFidelity,result=pcall(FidelityBuilder.run,mod,openColosseumDisc,function(label,current,total)
      BuildProgressUI.update(label,current,total)
    end)
    extractionStatus.audioFidelity=okFidelity and result or {ready=false,error=tostring(result)}
    -- Optional quality work never discards the known-playable soundtrack. If
    -- storage also prevented rollback, do not let runtime acquire partial data.
    if not okFidelity then FidelityBuilder.recover(mod) end
    if okFidelity and result.recoveryRequired then error(result.error,0) end
    if not(okFidelity and result.ready) and mod.log and mod.log.warn then
      pcall(mod.log.warn,mod.log,"Audio fidelity update incomplete; committed tracks retained. See build/audio_fidelity_v1/status.txt")
    end
  end
  BuildProgressUI.finish(extractionStatus.state,extractionStatus.message)
  if extractionStatus.state=="FAILED" and mod.log and mod.log.error then pcall(mod.log.error,mod.log,"CBE source build failed: %s",tostring(extractionStatus.message))
  elseif mod.log and mod.log.info then pcall(mod.log.info,mod.log,"CBE source build: %s",tostring(extractionStatus.state)) end
end
local okBuild,buildErr=pcall(runBuild)
if not okBuild then
  extractionStatus={state="FAILED",visualReady=false,audioReady=false,message=tostring(buildErr)}
  BuildProgressUI.finish("FAILED",tostring(buildErr))
  if mod.cache then pcall(mod.cache.write,mod.cache,"build/error.txt",tostring(buildErr).."\n") end
end

-- Source presentation is one contract. A CBE runtime may not advertise itself
-- as ready while its GC6E01 soundtrack cache is absent or incomplete: doing so
-- silently swaps Colosseum music for host-game audio and makes fidelity depend
-- on platform/cache history. Visual caches survive an audio failure, but CBE
-- remains behind the startup retry gate until both halves are complete.
while sourceImported and not startupExitRequested and (extractionStatus.visualReady~=true or extractionStatus.audioReady~=true) do
  local action=BuildProgressUI.failureGate(extractionStatus.state,extractionStatus.message,extractionStatus.trainerFirstError,extractionStatus.trainerSourceError)
  if action=="retry" then
    local okRetry,retryErr=pcall(runBuild)
    if not okRetry then
      extractionStatus={state="FAILED",visualReady=false,audioReady=false,message=tostring(retryErr)}
      BuildProgressUI.finish("FAILED",tostring(retryErr))
      if mod.cache then pcall(mod.cache.write,mod.cache,"build/error.txt",tostring(retryErr).."\n") end
    end
  elseif action=="delete_rebuild" then
    -- A hard generated-cache parse/schema failure must offer a real escape from
    -- retrying the same bytes forever. Arena failures get the narrow arena-only
    -- reset; other startup failures use the bounded active-runtime reset. Both
    -- explicitly preserve mod.imports (the user's GC6E01 source) and the byte-level
    -- preservation archive.
    local stateText=tostring(extractionStatus.state or ""):upper()
    local arenaFailure=stateText:find("ARENA",1,true)~=nil
    local resetFn=(arenaFailure and GeneratedCacheReset.resetArenas) or GeneratedCacheReset.reset
    local okCall,resetOK,resetMessage=pcall(resetFn,mod)
    if not okCall or resetOK~=true then
      local why=tostring(okCall and resetMessage or resetOK)
      extractionStatus={state="CACHE DELETE FAILED",visualReady=false,audioReady=false,message=why}
      BuildProgressUI.finish("CACHE DELETE FAILED",why)
    else
      cacheGateOutcome=arenaFailure and "failure-arena-delete-rebuild" or "failure-delete-rebuild"
      -- The scoped delete itself invalidates the affected transaction, so the
      -- normal incremental dispatcher rebuilds only what is now missing. Generic
      -- active-runtime deletion is already a fresh build and needs no second wipe.
      local okRetry,retryErr=pcall(runBuild)
      if not okRetry then
        extractionStatus={state="FAILED",visualReady=false,audioReady=false,message=tostring(retryErr)}
        BuildProgressUI.finish("FAILED",tostring(retryErr))
        if mod.cache then pcall(mod.cache.write,mod.cache,"build/error.txt",tostring(retryErr).."\n") end
      end
    end
  else
    cacheGateOutcome=action
    break
  end
end

local runtimeAllowed=extractionStatus.visualReady==true and extractionStatus.audioReady==true

local function module(name,arg)
  return package("lib/"..name..".lua",arg)
end
local namespace={mod=mod,FALLBACK=nil,engineRequire=require,
  -- Runtime sidecar repair uses the same release-stable retention primitive as
  -- the source extractors. Loading this tiny pure helper does no cache probing.
  PayloadPreserver=package("extract/PayloadPreserver.lua"),GeneratedCacheReset=GeneratedCacheReset}
local function loadModule(name,arg)
  local value=module(name,arg==nil and namespace or arg)
  namespace[name]=value
  return value
end

local Mat4=module("Mat4");namespace.Mat4=Mat4
loadModule("GeneratedAssets")
if PokemonExtractorRef and type(PokemonExtractorRef.installGeneratedAssets)=="function" then
  pcall(PokemonExtractorRef.installGeneratedAssets,namespace.GeneratedAssets)
end
loadModule("RuntimeMeshCache")
loadModule("WorkBudget")
loadModule("FrameWork")
namespace.MoveFXExtractor=MoveFXExtractorRef
loadModule("WazaPhasePolicy")
local MoveFXVM=loadModule("MoveFXVM")
loadModule("MoveFXSourceTravel")
local WazaSequenceRuntime=loadModule("WazaSequenceRuntime")
local GenerationCompat=loadModule("GenerationCompat")
local TrainerRig=loadModule("TrainerRig")
-- Shared trainer morph binding. MUST load before Trainer/PlayerTrainer.
loadModule("TrainerMorph")
local TrainerPerformance=loadModule("TrainerPerformance")
loadModule("BattleSides")
local FreeLookCamera=loadModule("FreeLookCamera")
local BattleAutoProgress=loadModule("BattleAutoProgress")
local BattleDirector=loadModule("BattleDirector")
local ModLookup=loadModule("ModLookup")
local TrainerRoster=loadModule("TrainerRoster")
local Trainer=loadModule("Trainer")
local PlayerTrainer=loadModule("PlayerTrainer")
local NativeTrainerSprites=loadModule("NativeTrainerSprites")
local MoveFXOwnership=loadModule("MoveFXOwnership")
local ArenaCatalog=loadModule("ArenaCatalog")
local ArenaAudienceProfile=loadModule("ArenaAudienceProfile")
local ArenaCacheIdentity=loadModule("ArenaCacheIdentity")
local BattleArtBridge=loadModule("BattleArtBridge")
loadModule("ShinySupport")
loadModule("ModelIdentity")
local CurrentSpriteModels=loadModule("CurrentSpriteModels")
loadModule("ColosseumDex")
loadModule("ColosseumDexNames")
loadModule("ColosseumPortraitIndex")
loadModule("ColosseumSpeciesIndex")
namespace.ColosseumPokemonMoveData=ColosseumPokemonMoveDataRef
namespace.ColosseumFontSource=ColosseumUIFontSourceRef
local ColosseumFont=loadModule("ColosseumFont")
mod.exports.colosseumFont=ColosseumFont
mod.exports.colosseumFontStatus=ColosseumFont.status()
local ColosseumVerifiedMoves=loadModule("ColosseumVerifiedMoves")
namespace.ColosseumVerifiedMoveStatus=ColosseumVerifiedMoves.install(mod,GenerationCompat.current())
loadModule("ColosseumMoveCatalog")
local ColosseumMoveTMs=loadModule("ColosseumMoveTMs")
namespace.ColosseumMoveTMStatus=ColosseumMoveTMs.install(mod,GenerationCompat.current())
mod.exports.colosseumMoveTMStatus=namespace.ColosseumMoveTMStatus
loadModule("ColosseumDexIdentity")
loadModule("ColosseumDexOwnedSidecar")
loadModule("ColosseumDexCatalog")
loadModule("ColosseumDexState")
loadModule("ColosseumDexOwnedStorage")
local ColosseumDexRuntime=loadModule("ColosseumDexRuntime")
local ColosseumDexMarkBridge=loadModule("ColosseumDexMarkBridge")
local ExpandedWildEncounters=loadModule("ExpandedWildEncounters")
loadModule("ColosseumDexHabitats")
local ColosseumDexSpecies=loadModule("ColosseumDexSpecies")
-- Registry writes belong to top-level initialization, before the host freezes
-- and merges content; mods.loaded MUST NOT re-register these records.
namespace.ColosseumDexSpeciesStatus=ColosseumDexSpecies.register(mod,GenerationCompat.current())
local ColosseumDexSaveBridge=loadModule("ColosseumDexSaveBridge")
local ColosseumDexGameplay=loadModule("ColosseumDexGameplay")
-- Save ownership must survive a presentation-cache retry. Keep the checked
-- reader/writer and dex ledger guards installed even when visual/audio startup
-- withholds the battle renderer. Encounter activation remains below.
ColosseumDexSaveBridge.install(mod,GenerationCompat.current())
ColosseumDexMarkBridge.install()
mod.exports.colosseumDexSpawns=ColosseumDexGameplay.status
local PokemonActors=loadModule("PokemonActors")
loadModule("RelicPresentation")
loadModule("SummitNumerals")
local Arena=loadModule("Arena")
loadModule("CameraPacing")
local Camera=loadModule("Camera")
local Music=loadModule("Music")
-- Mt. Battle entry flow needs one narrow piece of the shared soundtrack
-- service: play the retail Colosseum main-menu sequence while its Summit/Wes setup hub owns
-- the foreground, then restore the real overworld map song if the player backs
-- out. Expose the already-loaded service through the namespace before the
-- MtBattle modules are constructed; do not reload/duplicate Music.lua.
namespace.ColosseumMusic=Music
loadModule("BattleAudioSpec")
local BattleAudio=loadModule("BattleAudio")
local WazaAudioRuntime=loadModule("WazaAudioRuntime")
loadModule("WazaCameraFov")
loadModule("WazaCameraParams")
local WazaHandlers=loadModule("WazaHandlers")
local BattleMenuUI=loadModule("BattleMenuUI")
local CacheManager=loadModule("CacheManager")
local BattleSettings=loadModule("BattleSettings")
loadModule("AbilityData")
local Abilities=loadModule("Abilities")
loadModule("AbilityWeather")
local AbilityEffectsGen1=loadModule("AbilityEffectsGen1")
local AbilityEffectsGen2=loadModule("AbilityEffectsGen2")
local AbilityLifecycle=loadModule("AbilityLifecycle")
local Transition=loadModule("Transition")
local StandaloneHost=loadModule("StandaloneHost")
local StadiumBridge=loadModule("StadiumBridge")
local ResidentPrewarm=loadModule("ResidentPrewarm")
local BattleRuntime=loadModule("BattleRuntime")
namespace.BattleRuntime=BattleRuntime
namespace.DoublesCore=module("doubles/Core",namespace)
namespace.DoublesItems=module("doubles/Items",namespace)
namespace.DoublesNativeAdapter=module("doubles/NativeAdapter",namespace)
namespace.DoublesMovePresentation=module("doubles/MovePresentation",namespace)
namespace.ReleasePresentation=module("doubles/ReleasePresentation",namespace)
namespace.DoublesCamera=module("doubles/CameraDirector",namespace)
namespace.DoublesPresenter=module("doubles/Presenter",namespace)
namespace.DoublesRuntime=module("doubles/Runtime",namespace)
namespace.BossIntro=module("BossIntro",namespace)
-- Mt. Battle 100: foundational Phase 1 utility modules (save-state schema,
-- deterministic seeding, Level 50 cloning, XP Bank, Challenge Bag). Pure
-- libraries -- no install() step, no runtime hooks -- so they only need to
-- be loaded, not wired into installRuntime() below. Later Mt. Battle
-- phases (battle orchestration, hub UI) add their own loadModule calls and
-- an installRuntime() entry when they need one.
namespace.MtBattleSaveState=module("MtBattle/SaveState",namespace)
namespace.MtBattleSeedManager=module("MtBattle/SeedManager",namespace)
-- One tiny deterministic presentation plan per fight. Generated once when a
-- run seed is rolled and then reused by HubStage/Arena; no arena payload or
-- runtime mesh identity depends on it.
namespace.MtBattleSummitVariation=module("MtBattle/SummitVariation",namespace)
-- Challenge-local 001-386 mechanics/data projection. Loaded before every
-- consumer so Gen1/Gen2 host Data remains immutable while rentals/opponents can
-- resolve ColosseumDex species that do not exist in the native host PokÃ©dex.
namespace.MtBattleBattleData=module("MtBattle/BattleData",namespace)
namespace.MtBattleLevelClone=module("MtBattle/LevelClone",namespace)
namespace.MtBattleRentalPool=module("MtBattle/RentalPool",namespace)
namespace.MtBattleMovePrep=module("MtBattle/MovePrep",namespace)
namespace.MtBattleLevelLock=module("MtBattle/LevelLock",namespace)
namespace.MtBattleXPBank=module("MtBattle/XPBank",namespace)
namespace.MtBattleBattlePoints=module("MtBattle/BattlePoints",namespace)
namespace.MtBattleChallengeBag=module("MtBattle/ChallengeBag",namespace)
-- Mt. Battle 100: Phase 2 Adaptive Team Generator. Also pure libraries
-- (no install() step) -- RosterCore is a shared-logic helper Gen1/Gen2
-- generation both depend on, so it loads before them.
namespace.MtBattleArchetypes=module("MtBattle/Archetypes",namespace)
namespace.MtBattleFingerprint=module("MtBattle/Fingerprint",namespace)
namespace.MtBattleAntiRepeat=module("MtBattle/AntiRepeat",namespace)
namespace.MtBattleDifficulty=module("MtBattle/Difficulty",namespace)
namespace.MtBattleRosterCore=module("MtBattle/RosterCore",namespace)
-- RecordsManager has no load-order dependents; PlayerBehaviorTracker
-- MUST load before TeamGenGen1/2, though (RosterCore.behaviorLean reads
-- V.MtBattlePlayerBehaviorTracker once at TeamGenGen1/2's OWN
-- module-load time to build their behaviorCtx() helper -- the same
-- load-order hazard as BattleObserver/BattleLauncher below).
namespace.MtBattleRecordsManager=module("MtBattle/RecordsManager",namespace)
namespace.MtBattlePlayerBehaviorTracker=module("MtBattle/PlayerBehaviorTracker",namespace)
-- Supplemental design doc additions: Area Leaders, deterministic shiny
-- rolls, trainer identities/personalities. Loaded before TeamGenGen1/2
-- (which consume all three) and before TrainerPoolG1 (which needs
-- Difficulty.PERSONALITIES for the combined tier x personality ai_classes
-- registration).
namespace.MtBattleShinyRollManager=module("MtBattle/ShinyRollManager",namespace)
namespace.MtBattleAreaLeaderManager=module("MtBattle/AreaLeaderManager",namespace)
namespace.MtBattleTrainerIdentityGenerator=module("MtBattle/TrainerIdentityGenerator",namespace)
-- Fixed generation stipulations (legendary gate, the fight-49 Eeveelution
-- team, fight-100 double ace): loaded before TeamGenGen1/2, which read
-- V.MtBattleSpecialFights once at THEIR OWN module-load time (same
-- load-order hazard as PlayerBehaviorTracker above).
namespace.MtBattleSpecialFights=module("MtBattle/SpecialFights",namespace)
namespace.MtBattleTeamGenGen1=module("MtBattle/TeamGenGen1",namespace)
namespace.MtBattleTeamGenGen2=module("MtBattle/TeamGenGen2",namespace)
-- Mt. Battle 100: Phase 3 battle orchestration. TrainerPoolG1 needs an
-- install() call (content registration, mod-load-time only -- see its own
-- header) but that happens from installMtBattleTrainerPool() below, NOT
-- from installRuntime(), since installRuntime re-runs on mods.loaded and
-- a second :register for the same id errors (Phase 0 Spike 6).
namespace.MtBattleTrainerPoolG1=module("MtBattle/TrainerPoolG1",namespace)
-- Real battle-event capture for PlayerBehaviorTracker (closes the gap its
-- own header flagged as a follow-up): listens to the engine's real
-- battle.move_used/battle.battler_switched/battle.ended events, scoped
-- to one battle at a time. Loaded BEFORE BattleLauncher (which reads
-- V.MtBattleBattleObserver once at ITS OWN module-load time and attaches
-- it to every launched fight) -- load order matters here, unlike most of
-- this namespace's other cross-references.
namespace.MtBattleBattleObserver=module("MtBattle/BattleObserver",namespace)
namespace.MtBattleBattleLauncher=module("MtBattle/BattleLauncher",namespace)
namespace.MtBattleRunController=module("MtBattle/RunController",namespace)
-- Mt. Battle 100: Phase 4 hub UI + Phase 5 finale/XP distribution. All
-- still pure libraries except OverworldGate, which gets its own one-time
-- install() call below (mirrors TrainerPoolG1's pattern: talk-hook
-- wrapping must happen once, not on every installRuntime() re-run, or a
-- naive implementation would double-wrap -- OverworldGate.installTalkHook
-- guards against that itself via wrapTalkTo's __mtbWrapped check, so
-- unlike TrainerPoolG1 it is SAFE to call from installRuntime, but is
-- still called from the same one-time top-level site for consistency).
namespace.MtBattleHubStage=module("MtBattle/HubStage",namespace)
namespace.MtBattleMobileHubUI=module("MtBattle/MobileHubUI",namespace)
namespace.MtBattleHubScreens=module("MtBattle/HubScreens",namespace)
-- The real glue from "player talked to the NPC" to "team select ->
-- BEGIN CHALLENGE -> fight 1 launches" -- loaded BEFORE OverworldGate,
-- which reads V.MtBattleEntryFlow once at ITS OWN module-load time to
-- build its default onGateOpened handler (the same load-order hazard
-- documented at BattleObserver/BattleLauncher above).
namespace.MtBattleEntryFlow=module("MtBattle/EntryFlow",namespace)
namespace.MtBattleOverworldGate=module("MtBattle/OverworldGate",namespace)
namespace.MtBattleFinaleIntro=module("MtBattle/FinaleIntro",namespace)
namespace.MtBattleXPDistribution=module("MtBattle/XPDistribution",namespace)
-- Battle 100 post-result orchestration. battle.ended commits only deterministic
-- run state; BattleRuntime later calls its pump() at a stable overworld frame so
-- Gen 1 BattleReturn / Gen 2 native result teardown are never covered early.
namespace.MtBattlePostBattleFlow=module("MtBattle/PostBattleFlow",namespace)
namespace.MtBattleSuspendRun=module("MtBattle/SuspendRun",namespace)
-- Optional Scouting layer (supplemental design doc's own "future/
-- optional" framing) -- Scouting itself remains off by default. Battle
-- Abilities are a separate production feature and default ON.
namespace.MtBattleScoutingSystem=module("MtBattle/ScoutingSystem",namespace)

-- Mt. Battle 100: register the Gen 1 synthetic trainer-slot pool + its
-- five AI-difficulty ai_classes tiers, EXACTLY ONCE, here at top-level
-- mod-load time -- never inside installRuntime() (which reruns on
-- mods.loaded and would hit Registry's record-semantics rejection on a
-- second :register call for the same id, confirmed live in Phase 0
-- Spike 6). RATTATA is used as the placeholder party species: every
-- registered slot's placeholder is unconditionally overwritten by the
-- trainer.party hook before any real fight starts (BattleLauncher.lua
-- always supplies a real generated roster first), so the choice has no
-- gameplay impact -- it only needs to validate at mod-load time, and
-- RATTATA is present in every Gen 1 species set. Gen 2 never needs this pool:
-- BattleLauncher launches an inline CANLOSE trainer there, and the Gen 2
-- `trainers` registry uses a different class schema. Do not leak MTB_G1_* into
-- Gold/Crystal-class hosts.
local mtBattleHostGeneration=GenerationCompat.current()
if mtBattleHostGeneration==1 and mod.content and mod.content.trainers and mod.content.ai_classes then
  namespace.MtBattleTrainerPoolG1.install(mod,"RATTATA")
end
-- Overworld gate: OverworldGate.lua owns the verified generation-specific
-- defaults -- Gen 1 INDIGO_PLATEAU_LOBBY (2,9) and Gen 2
-- INDIGO_PLATEAU_POKECENTER_1F (1,12). The scientist offers the VR-headset
-- "MT. BATTLE cache install" (see EntryFlow.lua's showOffer); no coordinate
-- override is needed here. trainerModel stays "wes": that
-- controls who hosts the hub/arena presentation once inside, a separate
-- role from the overworld scientist who opens the gate.
namespace.MtBattleOverworldGate.install(mod,{trainerModel="wes"})
loadModule("QuickCachePlanner")
loadModule("CacheScreen")
local BattleCache=loadModule("BattleCache")

local function installRuntime(force)
  StadiumBridge.install()
  Music.install(mod)
  Music.attachGame(mod.game)
  BattleAudio.install(mod)
  namespace.MtBattleLevelLock.install(mod)
  BattleSettings.install(mod,Trainer,Music,ArenaCatalog,BattleMenuUI,CacheManager,TrainerRoster,GenerationCompat,AudioFidelity)
  -- Never install both kernels through the launcher facade: Gen I denies
  -- Gen II structs, while Gold's Gen I names may be presentation proxies.
  local abilityGeneration=GenerationCompat.current()
  if abilityGeneration==2 then AbilityEffectsGen2.installGlobal()
  else AbilityEffectsGen1.installGlobal() end
  AbilityLifecycle.install(mod,abilityGeneration)
  -- MOVE PREP's source-proven custom rows need two narrowly-scoped runtime
  -- corrections after the ability wrappers are in place: Colosseum's
  -- always-hit class bypasses accuracy without bypassing Fly/Dig, and Mirror
  -- Move must honor CommonMoveData's per-move copy flag. Both wrappers inspect
  -- only definitions carrying colosseumMoveId and leave native moves untouched.
  namespace.ColosseumVerifiedMoveRuntime=ColosseumVerifiedMoves.installRuntime(mod,abilityGeneration)
  -- Ordinary ColosseumDex gameplay owns checked persistence and encounters.
  -- Readiness is earned by real module installation, never a forced flag.
  ColosseumDexGameplay.install(mod,abilityGeneration)
  if ArenaCatalog.sync then ArenaCatalog.sync(mod.game) end
  Transition.install(mod)
  StandaloneHost.install(force)
  BattleArtBridge.install()
  ColosseumDexMarkBridge.install()
  -- CBE consumes its own Colosseum Pokemon models through the SAME documented
  -- battleActors v1 seam third-party providers use (PORTABLE_BATTLE_ACTORS.md),
  -- not a private path. CurrentSpriteModels skips handles whose id matches CBE's
  -- own and registerCapability rejects that id outright, so the service carries
  -- a distinct provider identity. When COLOSSEUM MODELS is ON the CBE arena
  -- consumes this service directly in both generations; when OFF the external
  -- provider/sprite selection remains authoritative.
  PokemonActors.install(PokemonExtractorRef,openColosseumDisc,CurrentSpriteModels,PKXMetadataRef)
  if MoveFXExtractorRef and type(MoveFXExtractorRef.install)=="function" then
    MoveFXExtractorRef.install(mod,openColosseumDisc)
  end
  CurrentSpriteModels.registerCapability(
    "COLOSSEUM_BATTLE_ENVIRONMENTS/pokemon","battleActors",PokemonActors.service)
  -- Give the F9 overlay a hook that runs every frame of a battle whatever the
  -- presentation mode. Idempotent: installRuntime is called again on
  -- mods.loaded, and wrapping an already-wrapped function would nest forever.
  if not CurrentSpriteModels.__cbePokemonDebugWrapped then
    local originalDrawWorld=CurrentSpriteModels.drawWorld
    CurrentSpriteModels.drawWorld=function(self,context)
      local ok,result=pcall(originalDrawWorld,self,context)
      pcall(PokemonActors.debugFrame)
      if not ok then error(result,0) end
      return result
    end
    CurrentSpriteModels.__cbePokemonDebugWrapped=true
  end
  MoveFXOwnership.install()
  if WazaHandlers and type(WazaHandlers.install)=="function" then WazaHandlers.install() end
  BattleRuntime.install()
  namespace.MtBattlePostBattleFlow.install(mod)
  namespace.DoublesRuntime.install()
  -- Install after DoublesRuntime so START suspension is the outer battle-update
  -- owner and remains reachable from both native and custom doubles command UI.
  namespace.MtBattleSuspendRun.install(mod)
  BattleAutoProgress.install()
  namespace.BossIntro.install()
  BattleCache.install()
end

if runtimeAllowed then
  FreeLookCamera.install()
  NativeTrainerSprites.install()
  installRuntime(false)
  if mod.events and type(mod.events.on)=="function" then
    mod.events:on("mods.loaded",function(payload)
      if ModLookup and type(ModLookup.setLoader)=="function" then
        ModLookup.setLoader(type(payload)=="table" and payload.loader or nil)
      end
      installRuntime(true)
    end)
    mod.events:on("game.ready",function(payload)
      local game=type(payload)=="table" and payload.game or nil
      if game then
        Music.attachGame(game)
        BattleAudio.attachGame(game)
        if ArenaCatalog.sync then ArenaCatalog.sync(game) end
        if BattleRuntime.attachFrame then BattleRuntime.attachFrame(game) end
        -- PERFORMANCE CACHE POLICY (1.9.16): game.ready only queues work.
        -- Arena/trainer/Pokemon uploads, framebuffer allocation, shader compile,
        -- and MoveFX cache promotion share one paced stable-overworld scheduler.
        -- This prevents multiple cache hits from becoming one giant GPU/disk/GC
        -- wall at save load while still making the resident cache progressively
        -- hotter before the user reaches the next battle or model-heavy UI.
        if ResidentPrewarm and type(ResidentPrewarm.queueStartup)=="function" then
          pcall(ResidentPrewarm.queueStartup,game)
        end

        if IS_ANDROID and mod.log and mod.log.info then
          pcall(mod.log.info,mod.log,"CBE Android performance-polish policy active: state-change guard + single paced resident-warm queue + runtime mesh sidecars + deferred mobile framebuffer")
        end
      end
    end)
  end
elseif mod.log and mod.log.warn then
  pcall(mod.log.warn,mod.log,"CBE runtime withheld because required generated visual/audio cache is not ready (%s)",tostring(cacheGateOutcome or extractionStatus.state))
end

-- Regenerate build/format_probe.txt on demand. The probe is otherwise written
-- once, on the first build that has it; this re-runs it without touching any
-- generated cache, so the WZX/CAM report can be refreshed at will.
mod.exports.battleAudioStatus=function() return BattleAudio.status() end
mod.exports.audioFidelityStatus=function() return AudioFidelity.status(mod) end

mod.exports.probeFormats=function()
  if not BuildPipelineRef then return false,"build pipeline unavailable (source not imported?)" end
  local ok,result,note=pcall(BuildPipelineRef.ensureFormatProbe,mod,nil,true)
  if not ok then return false,tostring(result) end
  return result==true,tostring(note or ""),"build/format_probe.txt"
end

-- Refresh Pokemon runtime state without deleting saved generated payload. The
-- next use revalidates current source/cache stamps and repairs stale derivatives
-- through preservation-aware writers. Destructive cache clearing remains solely
-- behind the explicit DELETE CACHE action.
mod.exports.rebuildPokemon=function()
  local ok,result=pcall(PokemonActors.rebuildSpecies)
  if not ok then return false,tostring(result) end
  return result==true,"Pokemon runtime refreshed; saved generated Pokemon cache retained"
end

mod.exports.rebuild=function()
  -- REBUILD refreshes current GC6E01 derivatives through preservation-aware
  -- component writers. Destructive deletion is a separate explicit cache action.
  local ok2,err2=pcall(runBuild,{forceRebuild=true});if not ok2 then return false,tostring(err2) end
  CacheManager.resetRuntime();return extractionStatus.visualReady,extractionStatus
end
-- Lightweight presentation-ownership query for UI/compatibility consumers.
--
-- Keep this deliberately separate from exports.status(): status() is a full
-- diagnostic report and may inspect generated-cache state. It is appropriate
-- for menus/logging, never for a battle update or draw loop. Ownership only
-- depends on already-live runtime tables, so this path performs no filesystem
-- work and is safe to sample at a battle boundary.
mod.exports.presentationOwnership=function(battle)
  local host=StandaloneHost.status()
  local runtime=BattleRuntime.status()
  local trainer=Trainer:status()
  local wild=type(battle)=="table" and battle.wild==true
  local world=host.active==true or runtime.active==true
  return {
    version=1,
    world=world,
    trainer=(not wild) and (host.active==true or trainer.active==true) or false,
    standalone=host.active==true,
    runtime=runtime.active==true,
  }
end

-- Full diagnostics. This may perform cache/status inspection and must not be
-- polled from frame-critical update/draw paths. Use presentationOwnership()
-- when a consumer only needs to know who owns the live battle presentation.
mod.exports.status=function()
  local stadium=StadiumBridge.status()
  return {version=VERSION,registered=stadium.registered,stadiumDelegated=stadium.delegated,arenaProviderId=stadium.arenaProviderId,cameraProviderId=stadium.cameraProviderId,stadium=stadium,
    runtime=BattleRuntime.status(),doubles=namespace.DoublesRuntime.service.status(),battleDirector=BattleDirector:status(),trainerRig=TrainerRig:status(),trainerPerformance=TrainerPerformance.status(),trainerRoster=TrainerRoster:status(),arena=Arena:status(),arenaCatalog=ArenaCatalog.status(mod.game,nil),trainer=Trainer:status(),playerTrainer=PlayerTrainer:status(),camera=Camera:status(),music=Music.status(),settings=BattleSettings.status(mod.game),cache=CacheManager.status(),extraction=extractionStatus,launcherImport=launcherCompat,battleMenuUI=BattleMenuUI.status(),transition=Transition.status(),nativeTrainerSprites=NativeTrainerSprites.status(),moveFxOwnership=MoveFXOwnership.status(),moveFxExtractor=MoveFXExtractorRef and MoveFXExtractorRef.status and MoveFXExtractorRef.status() or nil,moveFxVM={version=MoveFXVM.version,source=MoveFXVM.source},wazaSequenceRuntime=WazaSequenceRuntime and WazaSequenceRuntime.status and WazaSequenceRuntime:status() or nil,wazaHandlers=WazaHandlers and WazaHandlers.status and WazaHandlers.status() or nil,wazaAudio=WazaAudioRuntime and WazaAudioRuntime.status and WazaAudioRuntime:status() or nil,standaloneHost=StandaloneHost.status(),battleArtBridge=BattleArtBridge.status(),currentSpriteModels=CurrentSpriteModels.status(),pokemonActors=PokemonActors.status(),residentPrewarm=ResidentPrewarm and ResidentPrewarm.status and ResidentPrewarm.status() or nil,cacheGate={runtimeAllowed=runtimeAllowed,outcome=cacheGateOutcome}}
end
mod.exports.battleCompatibility={
  version=1,
  capabilities={sprites="battleSprites",actors="battleActors",presentation="battlePresentation",world="battleWorld"},
  register=function(owner,kind,provider) return CurrentSpriteModels.registerCapability(owner,kind,provider) end,
  unregister=function(owner,kind) return CurrentSpriteModels.unregisterCapability(owner,kind) end,
}
-- Expanded National-Dex service. This is deliberately additive: it exposes an
-- immutable 001-386 display/state view and strict sidecar codecs without
-- extending the host's native raw species-index or PokÃƒÆ’Ã‚Â©dex save tables.
mod.exports.colosseumDex={
  version=ColosseumDexRuntime.VERSION,maxDex=ColosseumDexRuntime.MAX_DEX,
  registry=function(_,request)
    request=type(request)=="table" and request or {}
    return ColosseumDexRuntime.registry(request.game or mod.game,request)
  end,
  snapshot=function(_,request)
    request=type(request)=="table" and request or {}
    return ColosseumDexRuntime.snapshot(request.game or mod.game,request)
  end,
  catalog=function(_,request)
    request=type(request)=="table" and request or {}
    return ColosseumDexRuntime.catalog(request.game or mod.game,request)
  end,
  listItems=function(_,request)
    request=type(request)=="table" and request or {}
    return ColosseumDexRuntime.listItems(request.game or mod.game,request)
  end,
  mark=function(_,save,generation,registry,identity,kind)
    return ColosseumDexRuntime.mark(save,generation,registry,identity,kind)
  end,
  prepareOwnedWrite=function(_,save,generation,registry)
    return ColosseumDexRuntime.prepareOwnedWrite(save,generation,registry)
  end,
  hydrateOwned=function(_,save,generation,registry)
    return ColosseumDexRuntime.hydrateOwned(save,generation,registry)
  end,
  habitats=function(_,request)
    request=type(request)=="table" and request or {}
    return namespace.ColosseumDexHabitats.locations(request.game or mod.game,request.species,request)
  end,
  spawnStatus=function() return ColosseumDexGameplay.status() end,
  persistenceStatus=function() return ColosseumDexRuntime.persistenceStatus() end,
}
-- Read-only information/showroom model bridge for Party/Summary UI surfaces.
-- This never starts battle presentation ownership. The standard resolver asks
-- CurrentSpriteModels which portable actor provider would win; resolveColosseum
-- explicitly requests CBE's source Pokemon actors for a Colosseum-branded pod.
local function cbeInformationContext(request)
  request=type(request)=="table" and request or {}
  local game=request.game or mod.game
  local mon=request.mon or request.pokemon
  local battler=request.battler
  if type(battler)~="table" and type(mon)=="table" then battler={mon=mon} end
  local enabled=true
  if BattleSettings and type(BattleSettings.pokemonModelsEnabled)=="function" then
    local ok,value=pcall(BattleSettings.pokemonModelsEnabled,game)
    enabled=(not ok) or value~=false
  end
  local context={
    apiVersion=1,game=game,battle=nil,
    sides={player={battler=battler},enemy={battler=nil}},
    phase="information",progress=1,groundY=0,
    services={cbeStandalone=true,informationSurface=true,informationAnimation=true},
  }
  if not enabled then return nil,"cbe-pokemon-models-disabled",context end
  return context,nil
end

-- Species-level (Pokedex dossier) and per-mon (Summary, in or out of
-- battle) ability resolution, usable whether or not a battle is active.
-- Read-only assignment. Runtime copies such as Trace are battle-local, and
-- inspecting Summary/PC/Pokedex never writes ability fields into saved Pokemon.
mod.exports.abilities={
  version=1,
  enabled=function() return Abilities.enabled(mod.game) end,
  speciesLabel=function(dex) return Abilities.speciesLabel(dex) end,
  nameFor=function(id) return Abilities.displayName(id) end,
  resolve=function(mon,def)
    if not mon then return nil end
    return Abilities.ensure(mon, Abilities.dexOf(mon,def))
  end,
}

mod.exports.battleCache={version=4,status=function()return BattleCache.status()end,
  -- Legacy prepare remains the explicit exhaustive API; new callers can select
  -- a startup-only pass or open the user's choice screen without baking.
  prepare=function(game)return BattleCache.openMenu(game or mod.game)end,
  prepareStartup=function(game)return BattleCache.requestStartup(game or mod.game)end,
  prepareQuick=function(game)return BattleCache.openQuick(game or mod.game)end,
  prepareFull=function(game)return BattleCache.openFull(game or mod.game)end,
  openMenu=function(game)return BattleCache.openMenu(game or mod.game)end}
mod.exports.informationModels={
  version=7,
  selected=function(_,request)
    return BattleCache.enabled(request and request.game or mod.game)
  end,
  resolve=function(_,request)
    if not runtimeAllowed then return nil,"cbe-runtime-unavailable" end
    return CurrentSpriteModels.informationActorProvider(request)
  end,
  resolveSelected=function(_,request)
    if not runtimeAllowed then return nil,"cbe-runtime-unavailable" end
    return CurrentSpriteModels.informationActorProvider(request)
  end,
  resolveColosseum=function(_,request)
    if not runtimeAllowed then return nil,"cbe-runtime-unavailable" end
    local context,reason=cbeInformationContext(request)
    if not context then return nil,reason end
    return PokemonActors.service,"cbe:colosseum-pokemon",context,mod.id
  end,
  -- Dedicated read-only Stats/Data showroom seam.  This intentionally does
  -- NOT inherit the live-battle COLOSSEUM MODELS toggle, which is save-local
  -- and may legitimately differ between Gen I and Gen II.  A UI information
  -- viewer does not claim battle actor ownership, mutate battle state, or
  -- change the player's selected battle sprite/model source.
  resolveShowroom=function(_,request)
    if not runtimeAllowed then return nil,"cbe-runtime-unavailable" end
    request=type(request)=="table" and request or {}
    local game=request.game or mod.game
    local mon=request.mon or request.pokemon
    local battler=request.battler
    if type(battler)~="table" and type(mon)=="table" then battler={mon=mon} end
    local context={
      apiVersion=1,game=game,battle=nil,
      sides={player={battler=battler},enemy={battler=nil}},
      phase="information",progress=1,groundY=0,
      services={cbeStandalone=true,informationSurface=true,informationAnimation=true,showroom=true},
    }
    return PokemonActors.service,"cbe:colosseum-pokemon",context,mod.id
  end,
  -- UI/CBE cooperative performance seam. These calls do no rendering and do
  -- not mutate gameplay. touchViewer temporarily prevents unrelated resident
  -- jobs from colliding with a model-heavy menu. requestResident queues the
  -- exact selected model/variant, including a first-use source-backed shiny,
  -- in cooperative slices while the viewer is open. Unstarted, superseded
  -- PC/Pokedex requests are pruned; active source work finishes safely.
  touchViewer=function(_,seconds,reason)
    if not runtimeAllowed or not (ResidentPrewarm and type(ResidentPrewarm.touchViewer)=="function") then return false end
    return ResidentPrewarm.touchViewer(seconds,reason)
  end,
  requestResident=function(_,request)
    if not runtimeAllowed then return false,"cbe-runtime-unavailable" end
    request=type(request)=="table" and request or {}
    local game=request.game or mod.game
    local mon=request.mon or request.pokemon
    local battler=request.battler
    if type(battler)~="table" and type(mon)=="table" then battler=mon end
    if not (ResidentPrewarm and type(ResidentPrewarm.queueInformation)=="function") then
      return false,"resident-prewarm-unavailable"
    end
    return ResidentPrewarm.queueInformation(game,battler,request.kind)
  end,
  workStatus=function(_,request)
    request=request or {}
    return PokemonActors.informationWorkStatus(request.game or mod.game,request.mon or request.battler)
  end,
  warmStatus=function(_,request)
    request=type(request)=="table" and request or {}
    local game=request.game or mod.game
    local mon=request.mon or request.pokemon
    local battler=request.battler
    if type(battler)~="table" and type(mon)=="table" then battler=mon end
    if PokemonActors and type(PokemonActors.informationWarmStatus)=="function" then
      return PokemonActors.informationWarmStatus(game,battler)
    end
    return nil
  end,
  -- Explicit information-viewer animation gate. UI 2.3.4+ uses this instead
  -- of mutating the actor table directly. This is showroom-only state and never
  -- changes live battle animation timing or source action selection.
  setAnimation=function(_,actor,enabled)
    if type(actor)~="table" then return false end
    actor.informationAnimation=enabled==true
    if enabled then
      actor._informationIdleNextCheck=nil
    end
    return true
  end,
}

mod.exports.controls={mouseOrbit="LMB DRAG",mouseDolly="RMB DRAG",mouseLens="SHIFT+RMB DRAG",mousePan="MMB DRAG",toggle="F8",orbitLeft="J",orbitRight="L",raise="I",lower="K",zoomIn="U",zoomOut="O",lensNarrow="N",lensWide="M",reset="HOME"}

-- Additive active-free-look description. Legacy controls export is retained
-- for old consumers; these mappings belong to FreeLookCamera rather than the
-- disabled legacy orbit handler. No new combat keys are registered here.
mod.exports.freeLookControls={version=2,setting="FREE LOOK CAMERA",mouseOrbit="RMB DRAG",
  mouseDolly="WHEEL / SHIFT+RMB DRAG",mousePan="MMB DRAG",touchOrbit="ONE-FINGER DRAG",
  touchDolly="PINCH",touchPan="TWO-FINGER DRAG",reset="HOME",doublesPersistent=true,
  ownership="additive-to-live-cinematic",gestureRegion="CENTRAL ARENA"}
