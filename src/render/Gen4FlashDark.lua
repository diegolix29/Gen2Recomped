-- THE DARK CAVES' DARKNESS (Platinum's OVERWORLD_WEATHER_DARK_FLASH, HGSS's
-- WEATHER_FLASH): everything black but a circle of light around the player.
--
-- pokeplatinum src/overlay005/ov5_021D5EB8.c, the DARK_FLASH weather task
-- (ov5_021DB04C): an H-blank window, one span per scanline, centred at
-- (128, 84) -- where the player stands on the 256 x 192 screen. On the map's
-- load the radius closes from 256 to 32 over 30 frames; when the weather
-- ends (Flash) it opens from 32 back to 256 and the darkness is gone. BG2,
-- the black layer, shows outside the window.
--
-- Drawn the cartridge's way, a span per row, so the edge keeps its steps.
-- `draw(w, h)` is Renderer.screenWeather's callback (UI pixels, the window's
-- full width); the circle stays at the player, centred across and 12 pixels
-- above the middle, as (128, 84) is on the DS.

local D = {}

D.SMALL, D.LARGE, D.FRAMES = 32, 256, 30
D.CENTRE_RISE = 96 - 84

D.state = nil  -- { map, from, to, t0, closing }
D.frame = 0    -- the overworld's frame counter, so the timing is in frames

local function now() return D.frame end

-- Called every frame the overworld draws, with the map and whether its
-- weather is the darkness right now. Answers whether anything is to be drawn.
function D.update(mapId, dark, frame)
  D.frame = tonumber(frame) or D.frame
  local st = D.state
  if dark then
    if not st or st.map ~= mapId or not st.closing then
      -- a dark map loaded (or the previous one was too): close in
      D.state = { map = mapId, from = D.LARGE, to = D.SMALL, t0 = now(), closing = true }
    end
    return true
  end
  if st and st.closing and st.map == mapId then
    -- the same map's darkness ended: Flash. Open out, then stop.
    local r = D.radius()
    D.state = { map = mapId, from = r, to = D.LARGE, t0 = now(), closing = false }
    return true
  end
  if st and not st.closing and st.map == mapId and D.radius() < D.LARGE then return true end
  D.state = nil
  return false
end

function D.radius()
  local st = D.state
  if not st then return D.LARGE end
  local k = math.min(1, math.max(0, now() - st.t0) / D.FRAMES)
  return st.from + (st.to - st.from) * k
end

function D.draw(w, h)
  if not D.state then return false end
  local g = love.graphics
  local r = D.radius()
  local cx, cy = math.floor(w / 2), math.floor(h / 2) - D.CENTRE_RISE
  g.setColor(0, 0, 0, 1)
  local top, bottom = math.max(0, math.floor(cy - r)), math.min(h, math.ceil(cy + r))
  if top > 0 then g.rectangle("fill", 0, 0, w, top) end
  if bottom < h then g.rectangle("fill", 0, bottom, w, h - bottom) end
  for y = top, bottom - 1 do
    local dy = y + 0.5 - cy
    local half = math.sqrt(math.max(0, r * r - dy * dy))
    local x0, x1 = math.floor(cx - half), math.ceil(cx + half)
    if x0 > 0 then g.rectangle("fill", 0, y, x0, 1) end
    if x1 < w then g.rectangle("fill", x1, y, w - x1, 1) end
  end
  g.setColor(1, 1, 1, 1)
  return true
end

return D
