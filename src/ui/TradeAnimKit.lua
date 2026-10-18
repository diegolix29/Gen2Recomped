-- Shared plumbing for the two Game Boy trade cinematics: Gen 1's
-- InternalClockTradeAnim (src/ui/TradeAnim.lua) and Gen 2's TradeAnimation
-- (src/ui/Gen2TradeAnim.lua).
--
-- Both are a fixed program of DelayFrames, register writes and PrintText
-- calls, so each screen runs its asm as a COROUTINE: one resume per 60 Hz
-- frame, `wait(n)` for DelayFrames n.  The timing then reads like the source
-- instead of a phase table nobody can check against it.
--
-- The text boxes are never pushed on the state stack.  The cartridge prints
-- them into the tilemap like any other tiles -- Gen 1 then slides the window
-- holding them off to the right (Trade_SlideTextBoxOffScreen), Gen 2 copies
-- them to the window and does the same (TradeAnim_ScrollOutRight) -- so the
-- screen owns a TextBox instance, steps it itself and draws it wherever the
-- layer it lives on happens to be.

local Font = require("src.render.Font")
local TextBox = require("src.render.TextBox")

local Kit = {}

-- ------------------------------------------------------------------ text

-- One of the trade's lines in the dataset's words, with `subs` spliced into
-- its {TOKEN}s.  nil when the dataset has no such line.  Gen 3 datasets carry
-- their own wording through TradeText; Gen 1/2 use the ROM text table.
function Kit.expand(game, key, subs)
  local TradeText = require("src.link.TradeText")
  local own = TradeText.forKey and TradeText.forKey(game.data, key, subs)
  if own then return TextBox.substitute(game, own) end
  local raw = game.data.text and game.data.text[key]
  if not raw then return nil end
  for token, value in pairs(subs or {}) do
    raw = raw:gsub("{" .. token:gsub("%p", "%%%0") .. "}",
                   (tostring(value):gsub("%%", "%%%%")))
  end
  return TextBox.substitute(game, raw)
end

-- A text box the screen drives by hand.  `instant` is Gen 1's
-- BIT_NO_TEXT_DELAY (set by LoadTradingGFXAndMonNames for the whole movie):
-- the whole box appears in the frame PrintText runs.  Otherwise it types at
-- the player's text speed, exactly as a field box does.
--
-- The box never waits for a button -- every trade line is one page and the
-- cartridge follows each with a fixed DelayFrames -- so a page break (none in
-- the vanilla lines; a mod's longer wording) advances on its own.
function Kit.textBox(game, text, instant)
  local input = setmetatable({}, { __index = game.input })
  local box
  function input.wasPressed(_, key)
    if box and box.waiting and (key == "a") then return true end
    return false
  end
  function input.isDown(self_, key)
    if instant and key == "a" then return true end
    return game.input and game.input.isDown and game.input:isDown(key) or false
  end
  local proxy = setmetatable({ input = input }, { __index = game })
  -- `stay` keeps a finished box on screen with no arrow and no pop: the
  -- screen decides when it goes away
  box = TextBox.new(proxy, text or "", nil, { stay = {} })
  if instant then
    for _ = 1, 4096 do
      if box.done then break end
      box:update(1 / 60)
    end
  end
  return box
end

function Kit.stepText(box)
  if box and not box.done then box:update(1 / 60) end
end

-- ------------------------------------------------------------------ shades

local GRAY = { [0] = { 1, 1, 1 }, { 2 / 3, 2 / 3, 2 / 3 },
               { 1 / 3, 1 / 3, 1 / 3 }, { 0, 0, 0 } }

-- A DMG palette register (rBGP / rOBP0 / rOBP1) as a colour-index -> shade
-- map: bits 2i+1..2i are the shade colour i shows as.
function Kit.dmgMap(register)
  local map = {}
  for i = 0, 3 do map[i] = math.floor(register / 4 ^ i) % 4 end
  return map
end

local IDENTITY = 0xE4

-- Draw `fn` through a DMG palette register: the art is stored as the four
-- raw colour indices (as greys) and comes out as the shades the register
-- picks, still grey, so the screen's palette zones colour it afterwards the
-- way the SGB / CGB colours the Game Boy's output.  The identity register
-- draws plainly.  Headless (no shader) it draws plainly too.
function Kit.withRegister(register, fn)
  if register == IDENTITY or register == nil then return fn() end
  local P = require("src.render.PaletteFX")
  local shader = love.graphics and love.graphics.setShader and P.shader()
  if not shader then return fn() end
  local map = Kit.dmgMap(register)
  love.graphics.setShader(shader)
  shader:send("c0", GRAY[map[0]])
  shader:send("c1", GRAY[map[1]])
  shader:send("c2", GRAY[map[2]])
  shader:send("c3", GRAY[map[3]])
  fn()
  love.graphics.setShader()
end

-- The same through a real CGB palette (Gen 2): `pal` is four {r,g,b} 0..255,
-- permuted by the DMG register the way DmgToCgbBGPals / DmgToCgbObjPal0 copy
-- wBGPals1 / wOBPals1 into the live palettes.
function Kit.withCgb(pal, register, fn)
  local P = require("src.render.PaletteFX")
  local shader = love.graphics and love.graphics.setShader and P.shader()
  if not (shader and pal) then return fn() end
  local map = Kit.dmgMap(register or IDENTITY)
  local function c(i)
    local col = pal[map[i] + 1]
    return { col[1] / 255, col[2] / 255, col[3] / 255 }
  end
  love.graphics.setShader(shader)
  shader:send("c0", c(0))
  shader:send("c1", c(1))
  shader:send("c2", c(2))
  shader:send("c3", c(3))
  fn()
  love.graphics.setShader()
end

-- ------------------------------------------------------------------ images

local images = setmetatable({}, { __mode = "v" })

-- An extracted sheet, or nil (and the screen draws its stand-in) when the
-- cache has none.  Assets.exists first: Assets.image hands back a
-- placeholder for a missing path, which would hide the gap.
function Kit.image(path)
  if type(path) ~= "string" then return nil end
  if images[path] ~= nil then return images[path] or nil end
  local Assets = require("src.render.Assets")
  local img
  if Assets.exists(Assets.resolve(path)) then
    local ok, loaded = pcall(Assets.image, path)
    img = ok and loaded or nil
  end
  images[path] = img or false
  return img
end

function Kit.forgetImages()
  for k in pairs(images) do images[k] = nil end
end
require("src.render.Assets").register(Kit.forgetImages)

local quads = setmetatable({}, { __mode = "k" })

-- 8x8 tile `index` (0-based) of a sheet `perRow` tiles wide
function Kit.tileQuad(img, index, perRow)
  local byImg = quads[img]
  if not byImg then byImg = {} quads[img] = byImg end
  local q = byImg[index]
  if not q then
    local iw, ih = img:getDimensions()
    perRow = perRow or math.floor(iw / 8)
    q = love.graphics.newQuad((index % perRow) * 8,
                              math.floor(index / perRow) * 8, 8, 8, iw, ih)
    byImg[index] = q
  end
  return q
end

-- one OBJ tile at OAM coordinates (the hardware's +8 / +16 offsets)
function Kit.drawObjTile(img, index, oamX, oamY, xflip, yflip, perRow)
  if not img then return end
  local x, y = oamX - 8, oamY - 16
  love.graphics.draw(img, Kit.tileQuad(img, index, perRow),
                     x + (xflip and 8 or 0), y + (yflip and 8 or 0), 0,
                     xflip and -1 or 1, yflip and -1 or 1)
end

-- a BG layer position on the 256-pixel wrap ring, as the left edge it is
-- drawn at on a 160-wide screen (nil = not visible)
function Kit.wrapX(px)
  local x = px % 256
  if x >= 248 then x = x - 256 end
  if x >= 160 then return nil end
  return x
end

-- PrintNumber with LEADING_ZEROES
function Kit.digits(n, width)
  return ("%0" .. width .. "d"):format(math.max(0, math.floor(tonumber(n) or 0))
                                        % (10 ^ width))
end

Kit.Font = Font

return Kit
