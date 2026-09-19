-- FireRed's SaveBlock2 layout differs from Emerald's.  The ROM manifest
-- supplies the common Gen 3 fields, while the extractor fills the FireRed
-- player fields that the save decoder needs.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local RomExtractorGen3 = require("src.import.RomExtractorGen3")
local S = require("tests.harness").suite("parity FireRed save layout")
local check = S.check

local sectorSizes = {
  3876, 3968, 3968, 3968, 3816,
  3968, 3968, 3968, 3968, 3968, 3968, 3968, 3968, 2000,
}

local function extract(isFireRed)
  local sectors = {}
  for _, size in ipairs(sectorSizes) do sectors[#sectors + 1] = { size = size } end
  local fields = {
    flagBytes = 288,
    varCount = 256,
    bag = {
      capacities = { 42, 30, 13, 58, 43 },
      pockets = { 784, 952, 1072, 1124, 1356 },
    },
    saveBlock1 = {
      flags = 3808, vars = 4096, gameStats = 4608,
      playerPartyCount = 52, playerParty = 56,
      money = 656, coins = 660, pcItems = 664,
    },
  }
  local fake = setmetatable({
    manifest = {
      metatileAttributes = { bytes = isFireRed and 4 or 2 },
      save = {
        sectorSize = 4096,
        sectorsPerSlot = 14,
        security = {},
        sectors = sectors,
        saveBlock2Size = 3876,
        saveBlock1Size = 15720,
        pokemonStorageSize = 33744,
      },
      substructOrders = { { 0, 1, 2, 3 } },
      saveFields = fields,
    },
  }, { __index = RomExtractorGen3 })

  function fake:beginStage() end
  function fake:write(name, value)
    if name == "save_layout" then self.layout = value end
  end
  function fake:berryTreeSaveBlock() return nil, "not in fixture" end
  function fake:mauvilleSaveBlock() return nil, "not in fixture" end
  function fake:decorationCapacities() return nil, "not in fixture" end
  function fake:berryPowderField() return nil end
  function fake:battlePointsField() return nil end
  function fake:dewfordPaintingField() return nil end

  fake:extractSaveLayout()
  return fields, fake.layout
end

local frFields, frLayout = extract(true)
check(frLayout and frLayout.fields.saveBlock2 ~= nil,
      "FireRed layout includes SaveBlock2 fields required by save decoder")
if frLayout and frLayout.fields.saveBlock2 then
  local block = frLayout.fields.saveBlock2
  check(block.playerName == 0, "FireRed player name starts at +0000")
  check(block.playerGender == 8, "FireRed player gender is at +0008")
  check(block.playerTrainerId == 10, "FireRed trainer ID is at +000A")
  check(block.playTimeHours == 14, "FireRed play-time hours are at +000E")
  check(block.playTimeMinutes == 16, "FireRed play-time minutes are at +0010")
  check(block.playTimeSeconds == 17, "FireRed play-time seconds are at +0011")
  check(block.playTimeVBlanks == 18, "FireRed play-time VBlanks are at +0012")
  check(block.encryptionKey == 0xF20,
        "FireRed encryption key is at +0F20, per its SaveBlock2 struct")
end
check(frLayout.fields.party ~= nil,
      "FireRed layout includes the party shape needed to decode party Pokemon")
if frLayout.fields.party then
  check(frLayout.fields.party.start == 56 and frLayout.fields.party.count == 52
          and frLayout.fields.party.size == 6
          and frLayout.fields.party.monSize == 100,
        "FireRed party shape matches six 100-byte Pokemon at +0038")
end
check(frLayout.fields.bag and frLayout.fields.bag.itemSlotSize == 4,
      "FireRed bag slots use the four-byte ItemSlot structure")
if frLayout.fields.bag then
  check(frLayout.fields.bag.pcItems == 664
          and frLayout.fields.bag.pcItemCount == 30,
        "FireRed PC item array fills the 120-byte gap before the bag")
end
check(frLayout.fields.storage ~= nil,
      "FireRed layout includes box storage so boxed Pokemon are decoded")
if frLayout.fields.storage then
  local storage = frLayout.fields.storage
  check(storage.currentBox == 0 and storage.boxes == 4
          and storage.boxCount == 14 and storage.boxCapacity == 30
          and storage.boxMonSize == 80,
        "FireRed storage begins after aligned current-box byte and has 14x30 boxes")
  check(storage.boxNames == 33604 and storage.boxNameLength == 9
          and storage.boxWallpapers == 33730,
        "FireRed box names and wallpapers follow the box records")
end

local _, emeraldLayout = extract(false)
check(emeraldLayout and emeraldLayout.fields.saveBlock2 == nil,
      "Emerald layout is not assigned FireRed-only SaveBlock2 offsets")

S.finish()
