-- THE POKeGEAR'S CARD / SKIN PICKER (overlay 101: pokegear_configure.c,
-- overlay_101_021EED44 / 021EF1D8 / 021EF6D0), the CONFIGURE app of
-- src/ui/HgssPokegear.lua.
--
-- READ FROM CODE:
--   * the screen: pgconf NSCR 16 + skin (MAIN_3); the open skin framed by
--     NSCR 22 + skin's 9 x 7 block at tile (10 (skin % 3) + 2, 9 (skin / 3) + 2)
--     on MAIN_2 (PokegearConfigure_SetNewSkin); every skin unlocked
--     (`unlockedSkins = 0xFF`, pokegear_configure.c:90)
--   * the cursor: conf OBJ seqs 0-3 around sCursorButtons -- centres (48 /
--     128 / 208, 44 / 116), corners at -22 / +22, -18 / +18, LEFT / RIGHT /
--     UP / DOWN along its links; it starts on skin 0
--   * touch: the six buttons y 24-64 / 96-136, x 24-72 / 104-152 / 184-232
--   * A or a tap: the CHANGE / QUIT menu (bank 270) at sContextMenuParam[skin]
--     (tile (10 / 20 / 22, 2 / 11), the third column right-aligned), the
--     rest of the screen dimmed 8 (PokegearConfigure_ToggleButtonFocusState);
--     CHANGE fades out, loads the skin's graphics everywhere and fades back
--     in over 6 frames each way (PokegearConfigure_SwapSkins)
--   * B: the cursor back on the bar

local TouchList = require("src.ui.HgssTouchList")

local Config = {}
Config.__index = Config

-- sCursorButtons: left, right, up, down, x, y
local CURSOR = {
  [0] = { 2, 1, 3, 3, 48, 44 }, { 0, 2, 4, 4, 128, 44 }, { 1, 0, 5, 5, 208, 44 },
  { 5, 4, 0, 0, 48, 116 }, { 3, 5, 1, 1, 128, 116 }, { 4, 3, 2, 2, 208, 116 },
}
-- sTouchscreenHitboxes (top, bottom, left, right)
local RECT = {
  [0] = { 24, 64, 24, 72 }, { 24, 64, 104, 152 }, { 24, 64, 184, 232 },
  { 96, 136, 24, 72 }, { 96, 136, 104, 152 }, { 96, 136, 184, 232 },
}
-- sContextMenuParam: x, y, right-aligned
local MENU_AT = { [0] = { 10, 2 }, { 20, 2 }, { 22, 2, true }, { 10, 11 }, { 20, 11 }, { 22, 11, true } }
local SWAP_FRAMES = 6

function Config.new(gear)
  return setmetatable({ gear = gear, game = gear.game, cursor = 0 }, Config)
end

function Config:openMenu(skin)
  self.selectedSkin = skin
  local at = MENU_AT[skin]
  local items = { self.gear:text(270, 0) or "CHANGE", self.gear:text(270, 1) or "QUIT" }
  self.menu = TouchList.new(self.gear, items, at[1], at[2], 0, { align = at[3] and "right" or nil })
  self.gear:se("SEQ_SE_GS_GEARDECIDE")
  self.busy = true
end

function Config:keys(input)
  if input:wasPressed("b") then return self.gear:toBar() end
  if input:wasPressed("a") then return self:openMenu(self.cursor) end
  local link = CURSOR[self.cursor]
  local to
  if input:wasPressed("left") then to = link[1]
  elseif input:wasPressed("right") then to = link[2]
  elseif input:wasPressed("up") then to = link[3]
  elseif input:wasPressed("down") then to = link[4] end
  if to then
    self.cursor = to
    self.gear:se("SEQ_SE_GS_GEARCURSOR")
  end
end

function Config:touch(x, y)
  for i = 0, 5 do
    local r = RECT[i]
    if y >= r[1] and y < r[2] and x >= r[3] and x < r[4] then
      self.cursor = i
      self:openMenu(i)
      return true
    end
  end
  return false
end

function Config:busyUpdate(input, tap)
  if self.swap then return end
  local r = self.menu and self.menu:update(input, tap)
  if r == nil then return end
  self.menu = nil
  if r == 0 then
    self.swap = { n = 0 }
  else
    self.busy = false
  end
end

function Config:update()
  local swap = self.swap
  if not swap then return end
  swap.n = swap.n + 1
  if swap.n == SWAP_FRAMES then
    -- PokegearConfigure_LoadAndSetSkin: the shell, the clock and this page
    local skin = self.selectedSkin or self.cursor
    self.gear.skin = skin
    self.gear:save().skin = skin
  end
  if swap.n >= SWAP_FRAMES * 2 then
    self.swap = nil
    self.busy = false
  end
end

function Config:reselect() end

function Config:drawTouch()
  local gear = self.gear
  gear:picture("config_top")
  local skin = gear.skin
  local sel = gear:img("config_sel")
  if sel then gear:tiles(sel, 0, 0, 9, 7, 10 * (skin % 3) + 2, 9 * math.floor(skin / 3) + 2) end
  if not gear.zone and not gear.fade then
    local c = CURSOR[self.cursor]
    gear:corners(c[5], c[6], -22, 22, -18, 18, "conf", 0)
  end
end

function Config:drawTouchOver()
  local g = love.graphics
  if self.menu then
    -- everything but the menu and the chosen button dimmed by 8
    local s = self.selectedSkin or 0
    local bx, by = 24 + (s % 3) * 80, 24 + math.floor(s / 3) * 72
    g.setColor(0, 0, 0, 0.5)
    g.rectangle("fill", 0, 0, 256, 192)
    g.setColor(1, 1, 1, 1)
    -- the window's hole over the chosen button: the page and its frame again
    local gear = self.gear
    local function again(img, ox, oy)
      if not img then return end
      local q = g.newQuad(bx - ox, by - oy, 48, 40, img:getDimensions())
      g.draw(img, q, bx, by)
    end
    again(gear:img("config_top"), 0, 0)
    if s == gear.skin then
      again(gear:img("config_sel"), (10 * (s % 3) + 2) * 8, (9 * math.floor(s / 3) + 2) * 8)
    end
    self.menu:draw()
  end
  local swap = self.swap
  if swap then
    local k = swap.n <= SWAP_FRAMES and swap.n / SWAP_FRAMES or (SWAP_FRAMES * 2 - swap.n) / SWAP_FRAMES
    g.setColor(0, 0, 0, k)
    g.rectangle("fill", 0, 0, 256, 192)
    g.setColor(1, 1, 1, 1)
  end
end

function Config:drawTop()
  local swap = self.swap
  if swap then
    local g = love.graphics
    local k = swap.n <= SWAP_FRAMES and swap.n / SWAP_FRAMES or (SWAP_FRAMES * 2 - swap.n) / SWAP_FRAMES
    g.setColor(0, 0, 0, k)
    g.rectangle("fill", 0, 0, 256, 192)
    g.setColor(1, 1, 1, 1)
  end
end

return Config
