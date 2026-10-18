-- HEARTGOLD / SOULSILVER'S TOUCH-SCREEN LIST MENU (touchscreen_list_menu.c),
-- the stacked buttons the Pokegear's apps pop up: the phone's "Call / Sort /
-- Quit" and "Title / Alphabet / Location / Move / Quit", the skin picker's
-- "CHANGE / QUIT".
--
-- READ FROM CODE:
--   * geometry: the frame at tile (x, y), `width` + 2 tiles wide and
--     3 * n + 1 tiles high; button i's window at tile (x + 1, y + 1 + 3 i),
--     `width` x 2 tiles, and its hitbox the same rectangle (16 px high)
--   * the frame's tiles (TouchscreenListMenu_DrawButtons) from sbox_gra:
--     top 0/1/2, sides 3/5, between 6/7/8, bottom 9/10/11, each + 12 next to
--     the cursor's button, + 18 for "between" when the button BELOW is it
--   * the window fills colour 3 with the words in 1 / 2; a pressed button
--     6 with 4 / 5 (TouchscreenListMenu_ToggleButtonPalette), held 8 frames
--     before the choice is answered
--   * keys: up / down wrap when the template says so, A presses, B cancels;
--     every move and press plays SEQ_SE_DP_SELECT
--   * the words centred when the template is `centered`
--
-- Answers from `update`: nil while open, the 0-based choice once the press
-- has run, or "cancel" for B.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")

local List = {}
List.__index = List

local floor = math.floor

function List.new(gear, items, x, y, width, opts)
  opts = opts or {}
  local self = setmetatable({ gear = gear, items = items, x = x, y = y, cursor = opts.cursor or 0,
    wrap = opts.wrap ~= false, centered = opts.centered ~= false, onMove = opts.onMove }, List)
  if not width or width == 0 then
    width = 0
    for _, s in ipairs(items) do width = math.max(width, math.ceil((Font.width(s) + 8) / 8)) end
  end
  if opts.align == "right" then self.x = math.max(0, x - (width + 2)) end
  self.width = width
  return self
end

function List:rect(i)
  local top = (self.y + 1) * 8 + 24 * i
  local left = (self.x + 1) * 8
  return left, top, self.width * 8, 16
end

function List:hit(px, py)
  for i = 0, #self.items - 1 do
    local l, t, w, h = self:rect(i)
    if px >= l and px < l + w and py >= t and py < t + h then return i end
  end
  return nil
end

-- tap: { x, y } in touch-screen pixels or nil
function List:update(input, tap)
  if self.pressed then
    self.pressed = self.pressed - 1
    if self.pressed <= 0 then return self.choice end
    return nil
  end
  if tap then
    local i = self:hit(tap.x, tap.y)
    if i then
      self.cursor, self.choice, self.pressed, self.touched = i, i, 8, true
      self.gear:se("SEQ_SE_DP_SELECT")
    end
    return nil
  end
  if not input then return nil end
  local n = #self.items
  if input:wasPressed("b") then
    self.gear:se("SEQ_SE_DP_SELECT")
    return "cancel"
  end
  if input:wasPressed("a") then
    self.choice, self.pressed, self.touched = self.cursor, 8, false
    self.gear:se("SEQ_SE_DP_SELECT")
    return nil
  end
  local before = self.cursor
  if input:wasPressed("up") then
    if self.wrap then self.cursor = (self.cursor + n - 1) % n elseif self.cursor > 0 then self.cursor = self.cursor - 1 end
  elseif input:wasPressed("down") then
    if self.wrap then self.cursor = (self.cursor + 1) % n elseif self.cursor < n - 1 then self.cursor = self.cursor + 1 end
  end
  if before ~= self.cursor then
    self.gear:se("SEQ_SE_DP_SELECT")
    if self.onMove then self.onMove(self.cursor) end
  end
  return nil
end

local function rgb(c, fallback)
  if type(c) ~= "table" then return fallback end
  return { (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255 }
end

function List:draw()
  local g = love.graphics
  local art = self.gear:art()
  local sheet = self.gear:image(art.sbox)
  local ink = art.sboxInk or {}
  local n = #self.items
  local last = n - 1
  local cur = self.cursor
  local x, y, w = self.x, self.y, self.width
  g.setColor(1, 1, 1, 1)
  local function tile(t, tx, ty)
    if not sheet then return end
    self.quads = self.quads or {}
    local q = self.quads[t]
    if not q then
      q = g.newQuad((t % 3) * 8, floor(t / 3) * 8, 8, 8, sheet:getDimensions())
      self.quads[t] = q
    end
    g.draw(sheet, q, tx * 8, ty * 8)
  end
  local function row(base, ty)
    tile(base, x, ty)
    for c = 1, w do tile(base + 1, x + c, ty) end
    tile(base + 2, x + w + 1, ty)
  end
  if sheet then
    row(cur == 0 and 12 or 0, y)
    row(cur == last and 21 or 9, y + n * 3)
    for i = 0, n - 2 do
      local base = 6
      if (cur == 0 and i == 0) or cur == i then base = 18
      elseif (cur == last and i == last - 1) or cur == i + 1 then base = 24 end
      row(base, y + i * 3 + 3)
    end
    for i = 0, n - 1 do
      local side = cur == i and 15 or 3
      for r = 1, 2 do
        tile(side, x, y + i * 3 + r)
        tile(side + 2, x + w + 1, y + i * 3 + r)
      end
    end
  else
    -- no frame art in this cache: the same rectangles, drawn
    g.setColor(0.32, 0.32, 0.35, 1)
    g.rectangle("fill", x * 8, y * 8, (w + 2) * 8, (n * 3 + 1) * 8)
  end
  for i = 0, n - 1 do
    local l, t, ww, hh = self:rect(i)
    local pressed = self.pressed and self.choice == i
    local fill = rgb(ink[pressed and 6 or 3], pressed and { 1, 0.97, 0.71 } or { 0.48, 0.77, 0.71 })
    g.setColor(fill[1], fill[2], fill[3], 1)
    g.rectangle("fill", l, t, ww, hh)
    if not sheet and cur == i then
      g.setColor(1, 0.1, 0.1, 1)
      g.rectangle("line", l - 1.5, t - 1.5, ww + 3, hh + 3)
    end
    local text = tostring(self.items[i + 1] or "")
    local tx = self.centered and (l + floor((ww - Font.width(text)) / 2)) or l
    Font.pushStyle({ text = rgb(ink[pressed and 4 or 1], { 0.94, 0.97, 0.97 }),
      shadow = rgb(ink[pressed and 5 or 2], { 0.32, 0.32, 0.35 }) })
    Font.draw(text, tx, t)
    Font.popStyle()
  end
  g.setColor(1, 1, 1, 1)
end

return List
