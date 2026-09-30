-- HD Pokémon import progress (same plate as Stadium extraction).
local V = ...
local Install = V.require("HdPokemonInstall")

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

local W, H = 160, 144
local Font = nil

local function font()
  if Font then return Font end
  local ok, F = pcall(require, "src.render.Font")
  if ok then Font = F end
  return Font
end

local function text(str, x, y)
  local F = font()
  if not F then return end
  love.graphics.setColor(0, 0, 0, 1)
  F.draw(str, math.floor(x), math.floor(y))
end

local function centred(str, y)
  local F = font()
  if not F then return end
  text(str, (W - F.width(str)) / 2, y)
end

function Screen.new(game)
  return setmetatable({ game = game, hold = 0 }, Screen)
end

function Screen:update()
  local st = Install.status
  if st.state == "importing" or st.state == "starting" then
    Install.poll()
    return
  end
  if st.state == "done" or st.state == "failed" or st.state == "idle" then
    self.hold = (self.hold or 0) + (love.timer and love.timer.getDelta and love.timer.getDelta() or 1 / 60)
    local input = self.game and self.game.input
    if (self.hold > 1.1) or (input and input.wasPressed and (
        input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start"))) then
      if self.game and self.game.stack and self.game.stack:top() == self then
        self.game.stack:pop()
      end
    end
  end
end

function Screen:draw()
  love.graphics.setColor(0.93, 0.94, 0.90, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)
  local st = Install.status or {}
  centred("HD POKEMON", 16)
  if st.state == "failed" then
    centred("IMPORT FAILED", 48)
    local err = tostring(st.error or "unknown")
    local y = 64
    while #err > 0 do
      centred(err:sub(1, 18), y)
      err = err:sub(19)
      y = y + 10
      if y > 110 then break end
    end
    centred("PRESS A", 128)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  if st.state == "done" then
    centred("READY", 48)
    centred(tostring(st.count or 0) .. " SPECIES", 64)
    centred("PRESS A", 128)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  centred("CONVERTING", 36)
  local cur = tonumber(st.current) or 0
  local total = math.max(1, tonumber(st.total) or 1)
  local frac = math.max(0, math.min(1, cur / total))
  local bx, by, bw, bh = 16, 56, 128, 9
  love.graphics.setColor(0.06, 0.05, 0.09, 1)
  love.graphics.rectangle("fill", bx - 1, by - 1, bw + 2, bh + 2)
  love.graphics.setColor(0.93, 0.94, 0.90, 1)
  love.graphics.rectangle("fill", bx, by, bw, bh)
  love.graphics.setColor(0.06, 0.05, 0.09, 1)
  love.graphics.rectangle("fill", bx, by, math.floor(bw * frac + 0.5), bh)
  love.graphics.setColor(0, 0, 0, 1)
  centred(("%d / %d"):format(cur, total), 72)
  local name = tostring(st.message or "")
  if #name > 18 then name = name:sub(1, 18) end
  if name ~= "" then centred(name, 88) end
  centred("PLEASE WAIT", 128)
  love.graphics.setColor(1, 1, 1, 1)
end

return Screen
