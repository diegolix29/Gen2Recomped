-- src/ui/HgssPokeathlonDataView.lua -- HEARTGOLD / SOULSILVER'S POKeATHLON
-- DATA MONITOR (the screen beside the Data Card counter, D49R0101's bg event
-- at (26, 9): "Which data would you like to see?" OVERALL / EVENT / ACTION
-- DATA, then ScrCmd_743 -> ov03_02258CFC). pokeheartgold
-- src/overlay_03/pokeathlon_records.c, transcribed:
--
--   * one window over the field, BG 3 at tile (2, 1), 28 x 22, palette 13,
--     the standard frame (ov03_02258DE8); the rows at (8, 8 + 16 i) in ink
--     (1, 2) on 15, the value right-aligned so it ends at 224 - 8
--   * page `type` (0 OVERALL, 1 EVENT, 2 ACTION) has 10 / 10 / 9 rows; row i
--     is record strno = 10 type + i, its label bank 277 #(strno + 4)
--   * a row is shown only when its Data Card was received -- the card for
--     strno is ov03_02259880[strno] - 1, and 0 there means always shown
--     (Times Joined, Event Last Place... the free rows); otherwise "???"
--     (#3) where the label would be, and no value
--   * the value (ov03_02259070) is a field of the save's record block
--     (Pokeathlon_UnkSubStruct_B00), capped at 9,999,999, printed in seven
--     right-aligned digits; strno 4 is the sum of the ten event wins; strno 9
--     (Time Spent) is minutes (one per 1800 frames, PokeathlonCourse_Exit)
--     shown as #2 "{hours 3 right}:{mins 2 zero-padded}",
--     the minutes capped at 999
--   * any touch, or A / B, closes it with SEQ_SE_DP_DECIDE (ov03_02258D88)
--
-- The record block's fields are kept on the save: the ones ScrCmd_724 also
-- reads stay where src/script/Gen4Commands.lua g4_athlon_record keeps them
-- (save.hgssPokeathlonRecords[0..17]), the rest under "b00_<offset>" keys.

local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")

local M = {}
M.__index = M
M.isOpaque = false

M.BANK = 277
M.ROWS = { [0] = 10, 10, 9 }
-- ov03_02259880: strno -> received Data Card + 1 (0 = always readable)
M.CARD = { [0] = 0, 1, 2, 25, 21, 22, 0, 19, 20, 27, 5, 7, 18, 8, 9, 17, 6, 16, 10, 24,
  26, 3, 4, 14, 23, 13, 11, 12, 15, 0, 0, 0 }
-- ScrCmd_724's index for each B00 field it reads (Gen4Commands g4_athlon_record)
M.REC_INDEX = { [0x4] = 12, [0x8] = 10, [0x14] = 13, [0x1C] = 14, [0x24] = 15,
  [0x2C] = 16, [0x30] = 17, [0x70] = 11 }
-- ov03_02259070: strno -> B00 field offset (10..19 are unk44[strno - 10])
M.FIELD = { [0] = 0x4, 0x8, 0xC, 0x10, "events", 0x6C, 0x38, 0x3C, 0x40, 0x0,
  [20] = 0x14, [21] = 0x2C, [22] = 0x1C, [23] = 0x24, [24] = 0x30, [25] = 0x34,
  [26] = 0x20, [27] = 0x18, [28] = 0x28 }
M.CAP = 9999999

function M:uiSize() return 256, 192 end
function M:wantsFillScale() return true end

-- a B00 field's value
function M.field(save, off)
  local rec = save and save.hgssPokeathlonRecords or {}
  if type(off) == "number" and off >= 0x44 and off < 0x44 + 40 then
    return tonumber(rec[(off - 0x44) / 4]) or 0
  end
  local idx = M.REC_INDEX[off]
  if idx then return tonumber(rec[idx]) or 0 end
  return tonumber(rec[("b00_%02X"):format(off)]) or 0
end

-- ov03_02259070
function M.value(save, strno)
  if strno >= 10 and strno <= 19 then return M.field(save, 0x44 + 4 * (strno - 10)) end
  local f = M.FIELD[strno]
  if f == "events" then
    local n = 0
    for i = 0, 9 do n = n + M.field(save, 0x44 + 4 * i) end
    return n
  end
  if f == nil then return 0 end
  return M.field(save, f)
end

-- ov03_02258ECC
function M.readable(save, strno)
  local card = M.CARD[strno] or 0
  if card == 0 then return true end
  return require("src.script.HgssPokeathlonShops").hasCard(save, card - 1)
end

function M.new(game, kind, onDone)
  kind = math.floor(tonumber(kind) or 0)
  if kind < 0 or kind > 2 then kind = 0 end
  return setmetatable({ game = game, kind = kind, onDone = onDone }, M)
end

local function line(self, n, fallback, ...)
  T.buffer(self.game, ...)
  local t = T.resolve(self.game.data, M.BANK, n, self.game)
  return (t and t ~= "") and t or fallback
end

local function padLeft(s, n, ch) s = tostring(s); return (ch or " "):rep(math.max(0, n - #s)) .. s end

-- the rows: { label, value or nil }
function M:rows()
  local out = {}
  local save = self.game.save
  for i = 0, M.ROWS[self.kind] - 1 do
    local strno = self.kind * 10 + i
    if M.readable(save, strno) then
      local v = math.min(M.CAP, M.value(save, strno))
      local text
      if strno == 9 then
        local mins, secs = math.min(999, math.floor(v / 60)), v % 60
        text = line(self, 2, ("%3d:%02d"):format(mins, secs), padLeft(mins, 3), padLeft(secs, 2, "0"))
      else
        text = padLeft(v, 7)
      end
      out[#out + 1] = { line(self, strno + 4, "?"), text }
    else
      out[#out + 1] = { line(self, 3, "???"), nil }
    end
  end
  return out
end

function M:close()
  if self.closed then return end
  self.closed = true
  pcall(function() require("src.core.Sound").playSe(self.game.data, "SEQ_SE_DP_DECIDE") end)
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function M:update()
  local input = self.game.input
  if input and (input:wasPressed("a") or input:wasPressed("b")) then self:close() end
end

function M:touchpressed() self:close(); return true end

function M:draw()
  -- the window (2, 1) 28 x 22 and its frame
  Font.drawBox(1, 0, 30, 24)
  love.graphics.setColor(0, 0, 0, 1)
  for i, r in ipairs(self:rows()) do
    local y = 8 + 8 + 16 * (i - 1)
    Font.draw(r[1], 16 + 8, y)
    if r[2] then
      local w = Font.width(r[2])
      Font.draw(r[2], 16 + 224 - w - 8, y)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return M
