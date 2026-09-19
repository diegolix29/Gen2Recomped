-- Generated Gen 3 type names must survive the built-in registry round-trip.
-- Run from the repository root with the ordinary Lua test runner.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("Gen 3 type categories")
local Registry = require("src.mods.Registry")
local Schemas = require("src.mods.Schemas")
local TypeChart = require("src.battle.TypeChart")

local registry = Registry.new("type_chart", Schemas.REGISTRIES.type_chart)
local data = {
  type_chart = {
    matchups = {},
    types = {
      PSYCHC = { id="PSYCHC", name="PSYCHC", index=14, category="special" },
      ELECTR = { id="ELECTR", name="ELECTR", index=13, category="special" },
      FIGHT = { id="FIGHT", name="FIGHT", index=1, category="physical" },
    },
  },
}

TypeChart.registerInto(registry, data, "engine")
S.eq(registry:get("PSYCHC").category, "special",
  "the FireRed Psychic type remains special")
S.eq(registry:get("ELECTR").category, "special",
  "the FireRed Electric type remains special")
S.eq(registry:get("FIGHT").category, "physical",
  "the FireRed Fighting type remains physical")
S.finish()
