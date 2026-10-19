-- Move IDs and badge IDs from Platinum's FieldMoves_Check* functions.
local F = {}
F.ids = {CUT=15,FLY=19,SURF=57,STRENGTH=70,FLASH=148,ROCK_SMASH=249,
  WATERFALL=127,ROCK_CLIMB=431,DEFOG=432,DIG=91,TELEPORT=100,SWEET_SCENT=230,
  CHATTER=448,MILK_DRINK=208,SOFTBOILED=135}
-- party_menu/main.c sFieldMoves: every move the party menu lists, whatever
-- the badges -- the check (field_move_tasks.c) answers at the press
F.ORDER = {'CUT','FLY','SURF','STRENGTH','DEFOG','ROCK_SMASH','WATERFALL','ROCK_CLIMB',
  'FLASH','TELEPORT','DIG','SWEET_SCENT','CHATTER','MILK_DRINK','SOFTBOILED'}
-- Badge-list positions follow TrainerInfo's IDs, not Platinum's gym visit order.
F.badges = {CUT=2,FLY=3,SURF=4,STRENGTH=6,DEFOG=5,ROCK_SMASH=1,WATERFALL=8,ROCK_CLIMB=7}
-- HEARTGOLD / SOULSILVER (pokeheartgold src/party_menu.c sFieldMoves,
-- src/field_move.c FieldMove_Check*, include/constants/std_script.h):
-- no Defog; Whirlpool and Headbutt; the badges are Johto's then Kanto's
-- (BADGE_ZEPHYR 0 .. BADGE_RISING 7, BADGE_EARTH 15 -> positions + 1); the
-- menu scripts are std_menu_* = 10000 + n in the `field_move` band.
F.ids.HEADBUTT, F.ids.WHIRLPOOL = 29, 250
F.HGSS_ORDER = {'CUT','FLY','SURF','STRENGTH','ROCK_SMASH','WATERFALL','ROCK_CLIMB','WHIRLPOOL',
  'FLASH','TELEPORT','DIG','SWEET_SCENT','CHATTER','HEADBUTT','MILK_DRINK','SOFTBOILED'}
F.HGSS_BADGES = {ROCK_SMASH=1,CUT=2,STRENGTH=3,SURF=4,FLY=5,WHIRLPOOL=7,WATERFALL=8,ROCK_CLIMB=16}
F.HGSS_BAND = 'field_move'
F.HGSS_MENU = {CUT=7,ROCK_SMASH=8,STRENGTH=9,ROCK_CLIMB=10,SURF=11,WATERFALL=12,FLASH=13,
  WHIRLPOOL=17,HEADBUTT=18}
-- Platinum's `scripts_field_moves` UseXFromMenu entries
F.PT_BAND = 'field_moves'
F.PT_MENU = {CUT=8,ROCK_SMASH=9,STRENGTH=10,ROCK_CLIMB=11,SURF=12,WATERFALL=13,DEFOG=14,FLASH=15}

function F.isHgss(data)
  local v = data and data.gen4_version
  if v and v.family then return v.family == 'hgss' end
  local ok, GV = pcall(require, 'src.core.GameVersion')
  return ok and GV.family and GV.family() == 'hgss' or false
end
function F.order(data) return F.isHgss(data) and F.HGSS_ORDER or F.ORDER end
function F.badgeTable(data) return F.isHgss(data) and F.HGSS_BADGES or F.badges end
-- band, entry of the move's party-menu script
function F.menuScript(data, name)
  if F.isHgss(data) then return F.HGSS_BAND, F.HGSS_MENU[name] end
  return F.PT_BAND, F.PT_MENU[name]
end

function F.knows(mon, name)
  if not mon or mon.egg or mon.isEgg then return false end
  local id = F.ids[name] or name
  for _, move in ipairs(mon.moves or {}) do
    local value = type(move)=='table' and move.id or move
    if value==id or value==name then return true end
  end
  return false
end
function F.badgeHeld(data, save, name)
  local position=F.badgeTable(data)[name]
  if not position then return true end
  local B=require('src.inventory.Badges');local entry=B.list(data)[position]
  if not entry then return false end
  return (save.badges and save.badges[entry.id]) or B.has(save,entry) or false
end
function F.partyMember(data, save, name)
  if not F.badgeHeld(data,save,name) then return end
  for _, mon in ipairs(save.party or {}) do if F.knows(mon,name) then return mon end end
end
-- THE TWO MOVES THE WEATHER OFFERS, and the band entry each one runs.
--
-- `FieldMoves_CanUseMoves` sets the FLASH and DEFOG usable bits from nothing
-- but the live weather:
--
--     case OVERWORLD_WEATHER_FOG:        ... FIELD_MOVE_FLAG(FIELD_MOVE_DEFOG)
--     case OVERWORLD_WEATHER_DARK_FLASH: ... FIELD_MOVE_FLAG(FIELD_MOVE_FLASH)
--
-- so neither is a badge-and-party question like Cut or Surf -- it is a
-- question about where you are standing. Offering them always would put two
-- rows on every party menu in Sinnoh that do nothing 591 maps out of 593.
--
-- The entry numbers are `scripts_field_moves.s`' own ScriptEntry table, in
-- order from zero: UseDefogFromMenu is 14 and UseFlashFromMenu is 15, which
-- `FieldMoves_FlashTask` confirms from the C side --
-- `ScriptManager_Change(taskMan, SCRIPT_ID(FIELD_MOVES, 15), NULL)`.
--
-- Running the cartridge's own script is what makes this worth doing rather
-- than writing the effect here: those two entries carry the message, the HM
-- cut-in, `DoFlashFunc FIELD_MOVE_FUNC_SET_ACTIVE` and the immediate
-- `ScrCmd_0C3`/`0C4` weather clear, and all four are already lowered.
F.WEATHER_MOVES = {
  DEFOG = { weather = "FOG",        entry = 14 },
  FLASH = { weather = "DARK_FLASH", entry = 15 },
}

-- True when the live weather is the one that offers this move.
--
-- `save.gen4WeatherActive` is the value `applyMapWeather` stored -- AFTER the
-- calendar resolution and after the substitution a field move already made --
-- which is why using Flash once takes the row off the menu for the rest of
-- that cave rather than leaving it there to be used again on a lit one.
function F.weatherOffers(save, name)
  local row = F.WEATHER_MOVES[name]
  if not row then return false end
  local W = require("src.import.Gen4Weather")
  return W.nameFor(save and save.gen4WeatherActive) == row.weather
end

-- Field_TrySetMapConnection (pokeplatinum overlay005/field_control.c;
-- pokeheartgold FieldSystem_TrySetMapConnection, field/field_control.c): the
-- special spawn Escape Rope and Dig return to is written on EVERY warp from a
-- map on the main matrix (matrix 0, `layout` here) to one that is not,
-- whatever either header's flags say -- so a cave entered through a gate or a
-- building records nothing new, and a building entered from a route does.
-- A cache whose defs carry no matrix falls back to the header flags.
function F.recordsEscape(from,dest)
  if not (from and dest) then return false end
  local a,b=tonumber(from.layout),tonumber(dest.layout)
  if a~=nil and b~=nil then return a==0 and b~=0 end
  return from.allowFly==true and dest.allowEscapeRope==true or false
end
-- ...stored as the player's tile and facing, one row further south when
-- facing north (Field_SetMapConnection)
function F.escapeCell(x,y,facing)
  if facing=='up' then y=y+1 end
  return x,y
end
return F
