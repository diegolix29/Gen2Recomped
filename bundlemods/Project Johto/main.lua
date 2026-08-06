return function(mod)
	-- Friendship evolutions
--	mod.content.evolution_methods:register("FRIENDSHIP", {
--	  check = function(game, mon, evo, trigger)
--		return trigger.kind == "levelup" and (mon.friendship or 0) >= 220
--	  end,
--	})

	-- Add Pokedex entries
	DunsparceDex = "To be added"
	mod.content.text:register("_DunsparceDexEntry", DunsparceDex)

-- Add Pokedex entries
	ShuckleDex = "To be added"
	mod.content.text:register("_ShuckleDexEntry", ShuckleDex)

-- Add Pokedex entries
	QwilfishDex = "To be added"
	mod.content.text:register("_QwilfishDexEntry", QwilfishDex)

-- Add Pokedex entries
	MisdreavusDex = "To be added"
	mod.content.text:register("_MisdreavusDexEntry", MisdreavusDex)

-- Add Pokedex entries
	StantlerDex = "To be added"
	mod.content.text:register("_StantlerDexEntry", StantlerDex)

-- Add Pokedex entries
	RaikouDex = "To be added"
	mod.content.text:register("_RaikouDexEntry", RaikouDex)

-- Add Pokedex entries
	EnteiDex = "To be added"
	mod.content.text:register("_EnteiDexEntry", EnteiDex)

-- Add Pokedex entries
	SuicuneDex = "To be added"
	mod.content.text:register("_SuicuneDexEntry", SuicuneDex)


	-- New Pokemon
	mod.content.pokemon:register("DUNSPARCE", {
	  id = "DUNSPARCE", 
	  name = "DUNSPARCE", 
	  dex = 206, 
	  dexEntry = { 
		heightFt = 4,
		heightIn = 11,
		kind = "LAND_SNAKE",
		weight = 30.9,
		text = "_DunsparceDexEntry"},
	  types = { "NORMAL" },
	  baseStats = { 
		hp = 100, 
		attack = 70, 
		defense = 70, 
		speed = 45, 
		special = 65 },
	  catchRate = 190, 
	  baseExp = 75, 
	  growthRate = "MEDIUM_FAST",
	  level1Moves = { "RAGE" }, 
	  learnset = {
		  { level = 13, move = "GLARE" },
		  { level = 30, move = "SCREECH" },
		  { level = 38, move = "TAKE_DOWN" },
		}, 
	  tms = {"TOXIC", "THUNDER", "SOLAR_BEAM", "DIG", "DOUBLE_TEAM", "REST", "STRENGTH"},
	  evolutions = {},
	  spriteFront = mod.assets:path("assets/dunsparce_front.png"),
	  spriteBack = mod.assets:path("assets/dunsparce_back.png"),
	  palette = "YELLOWMON",
	  frontSize = 4,
	})
	mod.content.cries:register("DUNSPARCE", { file = mod.assets:path("assets/dunsparce_cry.wav") })
	mod.content.icons:register("DUNSPARCE", {
	  image = "assets/generated/sprites/monster.png"
	})
	-- Area
	mod.content.encounters:patch("ROUTE_1", {
	  grass = { slots = { __prepend = { { species = "DUNSPARCE", level = 5 } } } },
	})

-- New Pokemon
	mod.content.pokemon:register("SHUCKLE", {
	  id = "SHUCKLE", 
	  name = "SHUCKLE", 
	  dex = 213, 
	  dexEntry = { 
		heightFt = 2,
		heightIn = 0,
		kind = "MOLD",
		weight = 45.2,
		text = "_ShuckleDexEntry"},
	  types = { "ROCK", "BUG" },
	  baseStats = { 
		hp = 20, 
		attack = 10, 
		defense = 230, 
		speed = 5, 
		special = 230 },
	  catchRate = 190, 
	  baseExp = 177, 
	  growthRate = "MEDIUM_SLOW",
	  level1Moves = { "CONSTRICT", "WITHDRAW" }, 
	  learnset = {
		  { level = 9, move = "WRAP" },
		  { level = 28, move = "BIDE" },
		  { level = 37, move = "REST" },
		}, 
	  tms = {"TOXIC", "DIG", "EARTHQUAKE", "DOUBLE_TEAM", "REST", "STRENGTH", "FLASH"},
	  evolutions = {},
	  spriteFront = mod.assets:path("assets/shuckle_front.png"),
	  spriteBack = mod.assets:path("assets/shuckle_back.png"),
	  palette = "YELLOWBAR",
	  frontSize = 4,
	})
	mod.content.cries:register("SHUCKLE", { file = mod.assets:path("assets/shuckle_cry.wav") })
	mod.content.icons:register("SHUCKLE", {
	  image = "assets/generated/sprites/monster.png"
	})
	-- Area
	mod.content.encounters:patch("VIRIDIAN_FOREST", {
	  grass = { slots = { __prepend = { { species = "SHUCKLE", level = 4 } } } },
	})
	mod.content.encounters:patch("ROCK_TUNNEL_1F", {
	  grass = { slots = { __prepend = { { species = "SHUCKLE", level = 16 }, { species = "SHUCKLE", level = 17 }, { species = "DUNSPARCE", level = 16 } } } },
	})
	mod.content.encounters:patch("ROCK_TUNNEL_B1F", {
	  grass = { slots = { __prepend = { { species = "SHUCKLE", level = 17 }, { species = "SHUCKLE", level = 18 }, { species = "DUNSPARCE", level = 17 } } } },
	})

-- New Pokemon
	mod.content.pokemon:register("QWILFISH", {
	  id = "QWILFISH", 
	  name = "QWILFISH", 
	  dex = 211, 
	  dexEntry = { 
		heightFt = 1,
		heightIn = 08,
		kind = "BALLOON",
		weight = 8.6,
		text = "_QwilFishDexEntry"},
	  types = { "WATER", "POISON" },
	  baseStats = { 
		hp = 65, 
		attack = 95, 
		defense = 85, 
		speed = 55, 
		special = 85 },
	  catchRate = 45, 
	  baseExp = 88, 
	  growthRate = "MEDIUM_FAST",
	  level1Moves = { "POISON_STING", "TACKLE" }, 
	  learnset = {
		  { level = 10, move = "HARDEN" },
		  { level = 10, move = "MINIMIZE" },
		  { level = 19, move = "WATER_GUN" },
		  { level = 28, move = "PIN_MISSILE" },
		  { level = 37, move = "TAKE_DOWN" },
		  { level = 46, move = "HYDRO_PUMP" },
		}, 
	  tms = {"TOXIC", "BLIZZARD", "SWIFT", "DOUBLE_TEAM", "REST", "SURF"},
	  evolutions = {},
	  spriteFront = mod.assets:path("assets/qwilfish_front.png"),
	  spriteBack = mod.assets:path("assets/qwilfish_back.png"),
	  palette = "GREENBAR",
	  frontSize = 4,
	})
	mod.content.cries:register("QWILFISH", { file = mod.assets:path("assets/qwilfish_cry.wav") })
	mod.content.icons:register("QWILFISH", {
	  image = "assets/generated/sprites/monster.png"
	})
	-- Area
	mod.content.encounters:patch("ROUTE_21", {
	  water = { slots = { __prepend = { { species = "QWILFISH", level = 15 } } } },
	})


	-- New Pokemon
	mod.content.pokemon:register("MISDREAVUS", {
	  id = "MISDREAVUS", 
	  name = "MISDREAVUS", 
	  dex = 200, 
	  dexEntry = { 
		heightFt = 2,
		heightIn = 04,
		kind = "SCREECH",
		weight = 2.2,
		text = "_MisdreavusDexEntry"},
	  types = { "GHOST" },
	  baseStats = { 
		hp = 60, 
		attack = 60, 
		defense = 60, 
		speed = 85, 
		special = 85 },
	  catchRate = 45, 
	  baseExp = 87, 
	  growthRate = "FAST",
	  level1Moves = { "GROWL", "PSYWAVE" }, 
	  learnset = {
		  { level = 12, move = "CONFUSE_RAY" },
		  { level = 27, move = "PSYBEAM" }
		}, 
	  tms = {"TOXIC", "THUNDER", "PSYCHIC", "SWIFT", "DOUBLE_TEAM", "REST", "FLASH"},
	  evolutions = {},
	  spriteFront = mod.assets:path("assets/misdreavus_front.png"),
	  spriteBack = mod.assets:path("assets/misdreavus_back.png"),
	  palette = "PURPLEMON",
	  frontSize = 4,
	})
	mod.content.cries:register("MISDREAVUS", { file = mod.assets:path("assets/misdreavus_cry.wav") })
	mod.content.icons:register("MISDREAVUS", {
	  image = "assets/generated/sprites/monster.png"
	})
	-- Area
	mod.content.encounters:patch("POKEMON_TOWER_5F", {
	  grass = { slots = { __prepend = { { species = "MISDREAVUS", level = 20 }, { species = "MISDREAVUS", level = 21 } } } },
	})
	mod.content.encounters:patch("POKEMON_TOWER_6F", {
	  grass = { slots = { __prepend = { { species = "MISDREAVUS", level = 22 }, { species = "MISDREAVUS", level = 23 } } } },
	})
	mod.content.encounters:patch("POKEMON_TOWER_7F", {
	  grass = { slots = { __prepend = { { species = "MISDREAVUS", level = 23 }, { species = "MISDREAVUS", level = 24 } } } },
	})


	-- New Pokemon
	mod.content.pokemon:register("STANTLER", {
	  id = "STANTLER", 
	  name = "STANTLER", 
	  dex = 234, 
	  dexEntry = { 
		heightFt = 4,
		heightIn = 07,
		kind = "BIG_HORN",
		weight = 157.0,
		text = "_StantlerDexEntry"},
	  types = { "NORMAL" },
	  baseStats = { 
		hp = 73, 
		attack = 95, 
		defense = 62, 
		speed = 85, 
		special = 85 },
	  catchRate = 45, 
	  baseExp = 163, 
	  growthRate = "SLOW",
	  level1Moves = { "TACKLE" }, 
	  learnset = {
		  { level = 8, move = "LEER" },
		  { level = 15, move = "HYPNOSIS" },
		  { level = 23, move = "STOMP" },
		  { level = 31, move = "SAND_ATTACK" },
		  { level = 40, move = "TAKE_DOWN" },
		  { level = 49, move = "CONFUSE_RAY" },
		}, 
	  tms = {"TOXIC", "EARTHQUAKE", "PSYCHIC", "SWIFT", "DOUBLE_TEAM", "REST", "FLASH"},
	  evolutions = {},
	  spriteFront = mod.assets:path("assets/stantler_front.png"),
	  spriteBack = mod.assets:path("assets/stantler_back.png"),
	  palette = "BROWNMON",
	  frontSize = 4,
	})
	mod.content.cries:register("STANTLER", { file = mod.assets:path("assets/stantler_cry.wav") })
	mod.content.icons:register("STANTLER", {
	  image = "assets/generated/sprites/monster.png"
	})
	-- Area
	mod.content.encounters:patch("ROUTE_14", {
	  grass = { slots = { __prepend = { { species = "STANTLER", level = 23 }, { species = "STANTLER", level = 24 } } } },
	})
	mod.content.encounters:patch("ROUTE_15", {
	  grass = { slots = { __prepend = { { species = "STANTLER", level = 23 }, { species = "STANTLER", level = 24 } } } },
	})

-- New Pokemon
	mod.content.pokemon:register("YANMA", {
	  id = "YANMA", 
	  name = "YANMA", 
	  dex = 193, 
	  dexEntry = { 
		heightFt = 3,
		heightIn = 11,
		kind = "CLEAR_WING",
		weight = 83.8,
		text = "_YanmaDexEntry"},
	  types = { "BUG", "FLYING" },
	  baseStats = { 
		hp = 65, 
		attack = 65, 
		defense = 45, 
		speed = 95, 
		special = 75 },
	  catchRate = 75, 
	  baseExp = 78, 
	  growthRate = "MEDIUM_FAST",
	  level1Moves = { "TACKLE" }, 
	  learnset = {
		  { level = 7, move = "QUICK_ATTACK" },
		  { level = 13, move = "DOUBLE_TEAM" },
		  { level = 19, move = "SONICBOOM" },
		  { level = 31, move = "SUPERSONIC" },
		  { level = 37, move = "SWIFT" },
		  { level = 43, move = "SCREECH" },
		}, 
	  tms = {"TOXIC", "GIGA_DRAIN", "SOLARBEAM", "DOUBLE_TEAM", "REST", "SWIFT", "FLASH"},
	  evolutions = {},
	  spriteFront = mod.assets:path("assets/yanma_front.png"),
	  spriteBack = mod.assets:path("assets/yanma_back.png"),
	  palette = "REDMON",
	  frontSize = 4,
	})
	mod.content.cries:register("YANMA", { file = mod.assets:path("assets/yanma_cry.wav") })
	mod.content.icons:register("YANMA", {
	  image = "assets/generated/sprites/monster.png"
	})
	-- Area
	mod.content.encounters:patch("ROUTE_24", {
	  grass = { slots = { __prepend = { { species = "YANMA", level = 11 } } } },
	})
	mod.content.encounters:patch("ROUTE_25", {
	  grass = { slots = { __prepend = { { species = "YANMA", level = 12 } } } },
	})

	-- New Pokemon
	mod.content.pokemon:register("RAIKOU", {
	  id = "RAIKOU", 
	  name = "RAIKOU", 
	  dex = 243, 
	  dexEntry = { 
		heightFt = 6,
		heightIn = 03,
		kind = "THUNDER",
		weight = 392.4,
		text = "_RaikouDexEntry"},
	  types = { "ELECTRIC" },
	  baseStats = { 
		hp = 90, 
		attack = 85, 
		defense = 75, 
		speed = 115, 
		special = 115 },
	  catchRate = 3, 
	  baseExp = 216, 
	  growthRate = "SLOW",
	  level1Moves = { "BITE", "LEER" }, 
	  learnset = {
		  { level = 11, move = "THUNDERSHOCK" },
		  { level = 21, move = "ROAR" },
		  { level = 31, move = "QUICK_ATTACK" },
		  { level = 51, move = "REFLECT" },
		  { level = 71, move = "THUNDER" },
		}, 
	  tms = {"TOXIC", "THUNDER", "HYPER_BEAM", "DIG", "DOUBLE_TEAM", "REST", "SWIFT", "CUT", "STRENGTH", "FLASH"},
	  evolutions = {},
	  spriteFront = mod.assets:path("assets/raikou_front.png"),
	  spriteBack = mod.assets:path("assets/raikou_back.png"),
	  palette = "YELLOWMON",
	  frontSize = 4,
	})
	mod.content.cries:register("RAIKOU", { file = mod.assets:path("assets/raikou_cry.wav") })
	mod.content.icons:register("RAIKOU", {
	  image = "assets/generated/sprites/monster.png"
	})
	-- Area
	mod.content.encounters:patch("SAFARI_ZONE_EAST", {
	  grass = { slots = { __prepend = { { species = "RAIKOU", level = 40 } } } },
	})

	-- New Pokemon
	mod.content.pokemon:register("ENTEI", {
	  id = "ENTEI", 
	  name = "ENTEI", 
	  dex = 244, 
	  dexEntry = { 
		heightFt = 6,
		heightIn = 11,
		kind = "VOLCANO",
		weight = 436.5,
		text = "_EnteiDexEntry"},
	  types = { "FIRE" },
	  baseStats = { 
		hp = 115, 
		attack = 115, 
		defense = 85, 
		speed = 100, 
		special = 90 },
	  catchRate = 3, 
	  baseExp = 217, 
	  growthRate = "SLOW",
	  level1Moves = { "BITE", "LEER" }, 
	  learnset = {
		  { level = 11, move = "EMBER" },
		  { level = 21, move = "ROAR" },
		  { level = 31, move = "FIRE_SPIN" },
		  { level = 41, move = "STOMP" },
		  { level = 51, move = "FLAMETHROWER" },
		  { level = 71, move = "FIRE_BLAST" },
		}, 
	  tms = {"TOXIC", "FIRE_BLAST", "HYPER_BEAM", "DIG", "DOUBLE_TEAM", "REST", "SWIFT", "CUT", "STRENGTH", "FLASH"},
	  evolutions = {},
	  spriteFront = mod.assets:path("assets/entei_front.png"),
	  spriteBack = mod.assets:path("assets/entei_back.png"),
	  palette = "REDBAR",
	  frontSize = 4,
	})
	mod.content.cries:register("ENTEI", { file = mod.assets:path("assets/entei_cry.wav") })
	mod.content.icons:register("ENTEI", {
	  image = "assets/generated/sprites/monster.png"
	})
	-- Area
	mod.content.encounters:patch("SAFARI_ZONE_NORTH", {
	  grass = { slots = { __prepend = { { species = "ENTEI", level = 40 } } } },
	})

	-- New Pokemon
	mod.content.pokemon:register("SUICUNE", {
	  id = "SUICUNE", 
	  name = "SUICUNE", 
	  dex = 245, 
	  dexEntry = { 
		heightFt = 6,
		heightIn = 07,
		kind = "AURORA",
		weight = 412.3,
		text = "_SuicuneDexEntry"},
	  types = { "WATER" },
	  baseStats = { 
		hp = 100, 
		attack = 75, 
		defense = 115, 
		speed = 85, 
		special = 115 },
	  catchRate = 3, 
	  baseExp = 215, 
	  growthRate = "SLOW",
	  level1Moves = { "BITE", "LEER" }, 
	  learnset = {
		  { level = 11, move = "WATER_GUN" },
		  { level = 21, move = "ROAR" },
		  { level = 31, move = "GUST" },
		  { level = 41, move = "BUBBLEBEAM" },
		  { level = 51, move = "MIST" },
		  { level = 71, move = "HYDRO_PUMP" },
		}, 
	  tms = {"TOXIC", "BLIZZARD", "HYPER_BEAM", "DIG", "DOUBLE_TEAM", "REST", "SWIFT", "CUT", "SURF"},
	  evolutions = {},
	  spriteFront = mod.assets:path("assets/suicune_front.png"),
	  spriteBack = mod.assets:path("assets/suicune_back.png"),
	  palette = "BLUEMON",
	  frontSize = 4,
	})
	mod.content.cries:register("SUICUNE", { file = mod.assets:path("assets/suicune_cry.wav") })
	mod.content.icons:register("SUICUNE", {
	  image = "assets/generated/sprites/monster.png"
	})
	-- Area
	mod.content.encounters:patch("SAFARI_ZONE_WEST", {
	  grass = { slots = { __prepend = { { species = "SUICUNE", level = 40 } } } },
	})



mod.content.pokemon:patch("DUNSPARCE", { battleScaleBack = 1 })
mod.content.icons:patch("DUNSPARCE", "SNAKE")

mod.content.battle_sprite_scales:register("dunsparce_back", {
  path = "assets/dunsparce_back.png",
  scale = 1,
})

mod.content.pokemon:patch("SHUCKLE", { battleScaleBack = 1 })
mod.content.icons:patch("SHUCKLE", "BUG")

mod.content.battle_sprite_scales:register("shuckle_back", {
  path = "assets/shuckle_back.png",
  scale = 1,
})

mod.content.pokemon:patch("QWILFISH", { battleScaleBack = 1 })
mod.content.icons:patch("QWILFISH", "WATER")

mod.content.battle_sprite_scales:register("qwilfish_back", {
  path = "assets/qwilfish_back.png",
  scale = 1,
})

mod.content.pokemon:patch("MISDREAVUS", { battleScaleBack = 1 })
mod.content.icons:patch("MISDREAVUS", "FAIRY")

mod.content.battle_sprite_scales:register("misdreavus_back", {
  path = "assets/misdreavus_back.png",
  scale = 1,
})

mod.content.pokemon:patch("STANTLER", { battleScaleBack = 1 })
mod.content.icons:patch("STANTLER", "QUADRUPED")

mod.content.battle_sprite_scales:register("stantler_back", {
  path = "assets/stantler_back.png",
  scale = 1,
})

mod.content.pokemon:patch("YANMA", { battleScaleBack = 1 })
mod.content.icons:patch("YANMA", "BUG")

mod.content.battle_sprite_scales:register("yanma_back", {
  path = "assets/yanma_back.png",
  scale = 1,
})

mod.content.pokemon:patch("RAIKOU", { battleScaleBack = 1 })
mod.content.icons:patch("RAIKOU", "QUADRUPED")

mod.content.battle_sprite_scales:register("raikou_back", {
  path = "assets/raikou_back.png",
  scale = 1,
})

mod.content.pokemon:patch("ENTEI", { battleScaleBack = 1 })
mod.content.icons:patch("ENTEI", "QUADRUPED")

mod.content.battle_sprite_scales:register("entei_back", {
  path = "assets/entei_back.png",
  scale = 1,
})

mod.content.pokemon:patch("SUICUNE", { battleScaleBack = 1 })
mod.content.icons:patch("SUICUNE", "QUADRUPED")

mod.content.battle_sprite_scales:register("suicune_back", {
  path = "assets/suicune_back.png",
  scale = 1,
})

end