-- src/import/Gen5MusicalData.lua -- THE POKEMON MUSICAL, FROM THE CARTRIDGE.
--
-- Everything Nimbasa's Musical Theater reads, decoded from Black / White
-- (nothing typed in from a guide). The facility's code lives in overlays 10
-- (musical_event.c, musical_dressup_sys.c, musical_stage_sys.c,
-- musical_program.c, scrcmd_musical.c), 112 (musical_system.c,
-- mus_item_data.c, mus_poke_draw.c), 131/132 (the stage) and 133 (the
-- dress-up, dup_fitting.c) -- the debug file names the overlays carry.
--
--   /a/0/4/5  member 101: THE PROPS' DATA (ov112 0x021F4F14 loads it whole;
--             0x021F4F54 = 12 bytes a prop): [0] the texture's size code
--             (0x22 32x32, 0x32 64x32, 0x23 32x64), [4] / [5] s8 x / y
--             offset, [6] the positions it may go (bit 0 ears, 1 head,
--             2 eyes, 3 face, 4 body, 5 waist, 6 hand, 7 back), [8] its kind
--             (0 ears .. 6 hand; 0x021F5158), [9] its TYPE (0 cool, 1 cute,
--             2 elegant, 3 quirky; 0x021F5140 -- what the scoring counts),
--             [10] the hand animation it appeals with.
--             members 0..99: each prop's texture (BTX0, "itemNN" + palette)
--   system bank 79  the props' names (prop n = entry n + 3; 0x05D kind 1),
--             bank 282 the same with an article (kind 8), bank 75 the
--             Musical's words (4 cool .. 9 balanced; 0x05D kinds 3 / 4 / 7)
--   /a/1/1/1 .. /a/1/1/4  THE FOUR SHOWS (Stardom, Forest Stroll, A Sweet
--             Soiree, Exciting Nimbasa): member 0 the program (ov10
--             0x02157028 reads it): [1..4] the four types' weights, [5] the
--             bonus pool (/ 5, dealt out at random in 5s), [6] the show's id,
--             then six performers of 0x2C bytes from +0xC: u16 species, u32
--             personality, u16 name, u16 the points the player needs before
--             they appear, then eight props { u16 prop (0x1FE / 0x1FF none),
--             u8 position, pad }. The songs are SEQ_BGM_MSL_01 .. 04.
--   /a/0/4/8  member 0: one 28-byte row per species / form (799): u16
--             species, u8 1 when it can play Dress Up (Koffing's row is 0).
--   arm9 0x0200A544: the save's new-game props (15 of them).
--   ov10 0x0216FF14: the fans' thresholds (ten u16, 12000 down to 0) and
--             0x0216FF28 the props fans give, 40 for each of 7 shows.
--
-- build(x) -> the record constants.gen5Musical (merged by Gen5Facilities).

local Narc = require("src.import.NarcArchive")

local M = {}

M.PATH = { props = "/a/0/4/5", species = "/a/0/4/8",
           shows = { "/a/1/1/1", "/a/1/1/2", "/a/1/1/3", "/a/1/1/4" } }
M.BANK = { propNames = 79, propNamesA = 282, words = 75 }
M.PROP_COUNT = 100
-- arm9 0x0200A57C .. 0x0200A5EE (the block's init): the props a new save owns
M.START_PROPS = { 0x30, 0x46, 0x53, 0x4B, 0x00, 0x01, 0x0A, 0x1C, 0x08, 0x3B, 0x3F, 0x42, 0x10, 0x59, 0x4C }
-- ov10 0x0215D83A: the fans' overworld sprites by show type (0x16A kind 0)
M.FAN_SPRITE = { [0] = 0x18, 0x0F, 0x2D, 0x0C }
M.SONGS = { [0] = "SEQ_BGM_MSL_01", "SEQ_BGM_MSL_02", "SEQ_BGM_MSL_03", "SEQ_BGM_MSL_04" }

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end
local function s8(v) return v >= 128 and v - 256 or v end

local function member(rom, path, m)
  local bytes = rom:read(path)
  local arc = bytes and Narc.parse(bytes)
  return arc and arc:get(m), arc
end

function M.props(rom, names)
  local d = member(rom, M.PATH.props, 101)
  if not d or #d < M.PROP_COUNT * 12 then return nil end
  local out = {}
  for i = 0, M.PROP_COUNT - 1 do
    local o = i * 12
    local size = d:byte(o + 1)
    out[i] = {
      size = size, width = math.floor(size / 16) == 3 and 64 or 32, height = size % 16 == 3 and 64 or 32,
      dx = s8(d:byte(o + 5)), dy = s8(d:byte(o + 6)), mask = d:byte(o + 7), flag7 = d:byte(o + 8),
      kind = d:byte(o + 9), type = d:byte(o + 10), appeal = d:byte(o + 11),
      name = names and names[i + 3] or ("Prop " .. i),
    }
  end
  return out
end

function M.show(rom, path, index)
  local d = member(rom, path, 0)
  if not d or #d < 12 + 6 * 0x2C then return nil end
  local show = { index = index, path = path, kind = d:byte(1), weights = {}, bonus = d:byte(6),
                 id = d:byte(7), performers = {}, song = M.SONGS[index] }
  for t = 0, 3 do show.weights[t] = d:byte(2 + t) end
  for k = 0, 5 do
    local o = 12 + k * 0x2C
    local p = { species = u16(d, o), personality = u32(d, o + 2), name = u16(d, o + 6),
                threshold = u16(d, o + 8), props = {} }
    for s = 0, 7 do
      local prop = u16(d, o + 12 + s * 4)
      if prop < 0x1FE then p.props[#p.props + 1] = { id = prop, pos = d:byte(o + 12 + s * 4 + 3) } end
    end
    show.performers[k] = p
  end
  return show
end

function M.species(rom)
  local d = member(rom, M.PATH.species, 0)
  if not d or #d < 4 then return nil end
  local n = u16(d, 0)
  local out = {}
  for i = 0, n - 1 do
    local o = 4 + i * 28
    local sp = u16(d, o)
    if sp > 0 and out[sp] == nil then out[sp] = d:byte(o + 3) == 1 end
  end
  return out
end

-- the fans' tables, found in overlay 10 by the thresholds' shape
function M.fanTables(rom)
  local ov10 = rom.overlay and rom:overlay(10)
  if not ov10 then return nil end
  local key = string.char(0xE0, 0x2E, 0x40, 0x1F, 0x7C, 0x15, 0xAC, 0x0D, 0xD0, 0x07, 0xE8, 0x03)
  local at = ov10:find(key, 1, true)
  if not at then return nil end
  local o = at - 1
  local thresholds = {}
  for i = 0, 9 do thresholds[i] = u16(ov10, o + i * 2) end
  local gifts = {}
  for s = 0, 6 do
    gifts[s] = {}
    for k = 0, 39 do gifts[s][k + 1] = ov10:byte(o + 20 + s * 40 + k + 1) end
  end
  return { thresholds = thresholds, gifts = gifts }
end

-- the props' pictures (BTX0 members 0..99), as PNGs when the extractor can save
function M.images(rom, saveImage)
  if not saveImage then return nil end
  local Models = require("src.import.Gen4Models")
  local bytes = rom:read(M.PATH.props)
  local arc = bytes and Narc.parse(bytes)
  if not arc then return nil end
  local out = {}
  for i = 0, M.PROP_COUNT - 1 do
    local b = arc:get(i)
    local okP, parsed = pcall(Models.parse, b)
    if okP and parsed and parsed.textures and parsed.textures[1] then
      local name = parsed.textures[1].name
      local pal = Models.paletteIndexByName and Models.paletteIndexByName(parsed, name .. "_pl") or 1
      local okD, image = pcall(Models.decode, parsed, b, 1, pal or 1)
      if okD and image then
        out[i] = saveImage(("bw_musical/prop_%02d"):format(i), image, { member = i })
      end
    end
  end
  return out
end

function M.build(x)
  local rom = x.rom
  local names, namesA, words = {}, {}, {}
  if x.string then
    for i = 0, M.PROP_COUNT + 2 do
      names[i] = x:string(M.BANK.propNames, i)
      namesA[i] = x:string(M.BANK.propNamesA, i)
    end
    for i = 0, 23 do words[i] = x:string(M.BANK.words, i) end
  end
  local props = M.props(rom, names)
  if not props then return nil end
  local rec = {
    source = "ROM:/a/0/4/5 (props) + /a/1/1/1-4 (shows) + /a/0/4/8 + ov10/arm9 tables",
    props = props, words = words, startProps = M.START_PROPS, fanSprite = M.FAN_SPRITE,
    shows = {}, species = M.species(rom),
  }
  for i = 0, M.PROP_COUNT - 1 do props[i].nameA = namesA[i + 3] end
  for i, path in ipairs(M.PATH.shows) do rec.shows[i - 1] = M.show(rom, path, i - 1) end
  local fans = M.fanTables(rom)
  if fans then rec.fanThresholds, rec.fanGifts = fans.thresholds, fans.gifts end
  local saveImage = x.saveImage and function(rel, image, extra) return x:saveImage(rel, image, extra) end
  rec.images = M.images(rom, saveImage)
  return rec
end

return M
