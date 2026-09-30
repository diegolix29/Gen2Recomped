-- HD Pokémon asset manager screen (KIM-style download / extract progress).
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

local function clip(str, n)
  str = tostring(str or "")
  if #str <= n then return str end
  return str:sub(1, n)
end

function Screen.new(game)
  return setmetatable({ game = game }, Screen)
end

local function pop(self)
  if self.game and self.game.stack and self.game.stack:top() == self then
    self.game.stack:pop()
  end
end

function Screen:update()
  Install.poll()
  local st = Install.status.state
  local input = self.game and self.game.input
  if not (input and input.wasPressed) then return end
  if st == "checking" or st == "downloading" then
    if input:wasPressed("b") then Install.cancel(); pop(self) end
    return
  end
  if st == "extracting" then return end
  if st == "error" then
    if input:wasPressed("a") then Install.startDownload(); return end
    if input:wasPressed("start") then Install.startLocalZip(self.game); return end
    if input:wasPressed("b") then pop(self) end
    return
  end
  if st == "done" then
    if input:wasPressed("a") or input:wasPressed("b") then pop(self) end
    return
  end
  if input:wasPressed("a") then Install.startDownload(); return end
  if input:wasPressed("start") then Install.startLocalZip(self.game); return end
  if input:wasPressed("b") then pop(self) end
end

function Screen:draw()
  love.graphics.setColor(0.93, 0.94, 0.90, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)
  local st = Install.status or {}
  centred("HD POKEMON", 8)
  centred("ASSET MANAGER", 18)
  local state = st.state or "idle"
  if state == "checking" then
    centred("CHECKING RELEASE", 52)
    centred("B CANCEL", 120)
  elseif state == "downloading" then
    centred("DOWNLOADING ZIP", 44)
    local have = math.floor((tonumber(st.downloadBytes) or 0) / 1000000)
    local total = math.floor((tonumber(st.downloadTotal) or 0) / 1000000)
    if total > 0 then
      centred(string.format("%d/%d MB", have, total), 64)
    else
      centred(string.format("%d MB", have), 64)
    end
    centred("ONE-TIME DOWNLOAD", 84)
    centred("B CANCEL", 120)
  elseif state == "extracting" then
    centred("INSTALLING", 40)
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
    centred(clip(st.message, 18), 88)
    centred("PLEASE WAIT", 120)
  elseif state == "error" then
    centred("INSTALL ERROR", 36)
    local err = tostring(st.error or "unknown")
    local y = 52
    while #err > 0 and y < 110 do
      centred(err:sub(1, 18), y)
      err = err:sub(19)
      y = y + 10
    end
    centred("A RETRY  B BACK", 128)
  elseif state == "done" then
    centred("ASSETS READY", 52)
    centred(tostring(st.count or 0) .. " SPECIES", 68)
    centred("A CONTINUE", 120)
  else
    centred("A DOWNLOAD PACK", 48)
    centred("START LOCAL ZIP", 64)
    centred("ANDROID: PUT ZIP IN", 84)
    centred("SAVE AS", 94)
    centred("picked_hd_pokemon.zip", 104)
    centred("B BACK", 128)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Screen
