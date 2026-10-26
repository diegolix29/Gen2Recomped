-- HEARTGOLD / SOULSILVER POKeATHLON: THE PER-EVENT SOLO RECORDS
-- (pokeheartgold include/pokeathlon/pokeathlon_save.h Pokeathlon_RecordsSolo
-- recordsSolo[10] at PokeathlonSave+0x2CC, and asm/overlay_96.s
-- ov96_021E839C / 021E7BA8 / 021E7938 / 021E7C04 / 021E7D30).
--
-- READ FROM CODE:
--   * an event's record entry (0x2C bytes): five Pokeathlon_CourseEntry
--     {u16 score, u16 mons[3]} best first, then a u32 play count;
--     PokeathlonSave_Init fills every score with 0xFFFF (no record)
--   * the mons are (form << 10) + species of the team's three (021E7938
--     from the participant's +4 / +0x2C / +0x54 u16 pair)
--   * _0221A7D8[event] = 01 00 00 00 00 00 00 00 00 00: Hurdle Dash's is a
--     time (lower is better), the other nine's a count (higher is better)
--   * "beats" (021E7D30, also 021E839C's test): the old score is 0xFFFF, or
--     strictly better -- a tie is not a record
--   * NEW RECORD! (021E839C, called by the FINISH 021E667C after its 61
--     ticks): the event's value (the u16 each event hands ov96_021E8318 when
--     it ends -> data+0xD2A, 0xFFFF from the event's start 021E6CE4) beats
--     recordsSolo[event].entries[0]
--   * THE SAVE (021E7718, the course's end, after the Athlete Points;
--     solo only -- a link course writes recordsLink instead): for each of
--     the course's three events, in order --
--       021E7BA8: if the event's result score (data+0x8D4 = the results'
--         field_5F0 = the event's field_5E0) beats entries[0], unk_AEC[event]
--         (u16 x 10, PokeathlonSave+0xAEC) = the event's Athlete Points
--         (data+0x8B4); then
--       021E7938: plays += 1 (to 9999999), and the result score with the
--         team's three goes into the top five (021E7C04: it replaces the
--         fifth if it beats it, then rises while it beats the one above)
--   * the value 021E839C compares is not always the one saved: Hurdle Dash
--     hands 021E8318 the raw sum of its three finish ticks but saves
--     field_5E0 = that sum cut to tenths of a second (021FBDEC); Relay Run
--     caps the laps at 60 for 021E8318 only. The events pass both.
--
-- THE PORT'S SAVE: save.hgssPokeathlonEventRecords[event 0..9] =
--   { plays = n, [1..5] = { score = u16, mons = { u16, u16, u16 } } }
-- (a missing entry or slot is 0xFFFF, no record), and
-- save.hgssPokeathlonEventPoints[event] = unk_AEC's u16. The Data Monitor
-- (src/ui/HgssPokeathlonDataView.lua) shows the Pokeathlon_UnkSubStruct_B00
-- counters, not these.

local M = {}

M.EMPTY = 0xFFFF
M.PLAYS_MAX = 9999999                     -- 0x0098967F
M.LOWER_BETTER = { [0] = true }           -- _0221A7D8

local function u16(v) return math.floor(tonumber(v) or 0) % 65536 end

-- 021E7D30: `new` beats `old`
function M.beats(event, old, new)
  old, new = u16(old), u16(new)
  if old == M.EMPTY then return true end
  if M.LOWER_BETTER[event] then return old > new end
  return old < new
end

-- the event's entry (nil when there is none and `create` is false)
function M.entry(save, event, create)
  if type(save) ~= "table" then return nil end
  local all = save.hgssPokeathlonEventRecords
  if type(all) ~= "table" then
    if not create then return nil end
    all = {}
    save.hgssPokeathlonEventRecords = all
  end
  local e = all[event]
  if type(e) ~= "table" then
    if not create then return nil end
    e = { plays = 0 }
    all[event] = e
  end
  return e
end

-- entries[k].score (k 1..5), 0xFFFF when empty
function M.score(save, event, k)
  local e = M.entry(save, event, false)
  local slot = e and e[k or 1]
  if type(slot) ~= "table" or slot.score == nil then return M.EMPTY end
  return u16(slot.score)
end

function M.best(save, event) return M.score(save, event, 1) end

-- 021E839C: whether the event's value is a NEW RECORD! (solo)
function M.isNew(game, event, value)
  if value == nil then return false end
  local save = game and game.save
  return M.beats(event, M.best(save, event), value)
end

local function packMon(m)
  if type(m) ~= "table" then return 0 end
  local species = math.floor(tonumber(m.species) or 0) % 1024
  local form = math.floor(tonumber(m.form) or 0) % 64
  return u16(form * 1024 + species)
end

-- 021E7BA8 + 021E7938: the course's end. `events` the course's event ids,
-- `scores[i]` event i's result score (field_5E0; nil skips the event),
-- `points[i]` its Athlete Points, `team` the player's three Pokemon
function M.commit(save, events, scores, points, team)
  if type(save) ~= "table" or type(events) ~= "table" or type(scores) ~= "table" then return end
  -- 021E7BA8 first, against the bests before this course's are added
  for i, ev in ipairs(events) do
    local s = scores[i]
    if s ~= nil and M.beats(ev, M.best(save, ev), s) then
      save.hgssPokeathlonEventPoints = save.hgssPokeathlonEventPoints or {}
      save.hgssPokeathlonEventPoints[ev] = u16(points and points[i])
    end
  end
  local mons = {}
  for m = 1, 3 do mons[m] = packMon(team and team[m]) end
  for i, ev in ipairs(events) do
    local s = scores[i]
    if s ~= nil then
      local e = M.entry(save, ev, true)
      local plays = math.floor(tonumber(e.plays) or 0)
      if plays < M.PLAYS_MAX then e.plays = plays + 1 end
      -- 021E7C04: in at the fifth place if it beats it, then up
      local list = {}
      for k = 1, 5 do
        local slot = e[k]
        if type(slot) == "table" and slot.score ~= nil then
          list[k] = { score = u16(slot.score), mons = { u16((slot.mons or {})[1]), u16((slot.mons or {})[2]), u16((slot.mons or {})[3]) } }
        else
          list[k] = { score = M.EMPTY, mons = { 0, 0, 0 } }
        end
      end
      local cand = { score = u16(s), mons = { mons[1], mons[2], mons[3] } }
      if M.beats(ev, list[5].score, cand.score) then
        list[5] = cand
        for k = 5, 2, -1 do
          if not M.beats(ev, list[k - 1].score, list[k].score) then break end
          list[k - 1], list[k] = list[k], list[k - 1]
        end
      end
      for k = 1, 5 do e[k] = list[k] end
    end
  end
end

return M
