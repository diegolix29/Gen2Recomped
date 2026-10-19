-- src/ui/Gen5MusicalArt.lua -- drawing a Pokemon in its Musical props.
--
-- The props' pictures are the cartridge's own textures (/a/0/4/5 members
-- 0..99, constants.gen5Musical.images) and their x / y offsets the prop
-- table's (bytes 4 / 5). WHERE ON THE POKEMON each position sits is NOT the
-- cartridge's: Black / White place props on per-species points of the
-- Musical's own MCSS poses (/a/0/4/8 points at them), which this port does
-- not decode yet. Here a position is a point on the front sprite's opaque
-- box -- ears at its top corners, the head at its top, eyes / face in its
-- upper middle, body / waist lower down, the hands at its sides.

local Assets = require("src.render.Assets")

local M = {}
local lg = love and love.graphics

local imgCache, boxCache = {}, {}

function M.image(path)
  -- a picture already in memory (a harness decoding the ROM on the spot)
  if type(path) == "table" and path.image then return path.image end
  if type(path) == "table" then path = path.path end
  if type(path) ~= "string" then return nil end
  if imgCache[path] == nil then
    local ok, img = pcall(Assets.image, path)
    if ok and img then img:setFilter("nearest", "nearest") end
    imgCache[path] = ok and img or false
  end
  return imgCache[path] or nil
end

-- the opaque box of a picture, in its own pixels
function M.box(path)
  if type(path) ~= "string" then return nil end
  if boxCache[path] == nil then
    local box = false
    local ok, data = pcall(Assets.imageData, path)
    if ok and data then
      local w, h = data:getDimensions()
      local x0, y0, x1, y1 = w, h, -1, -1
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local _, _, _, a = data:getPixel(x, y)
          if a > 0.1 then
            if x < x0 then x0 = x end
            if x > x1 then x1 = x end
            if y < y0 then y0 = y end
            if y > y1 then y1 = y end
          end
        end
      end
      if x1 >= x0 then box = { x0 = x0, y0 = y0, x1 = x1, y1 = y1, w = w, h = h } end
    end
    boxCache[path] = box
  end
  return boxCache[path] or nil
end

function M.front(data, species)
  local def = data and data.pokemon and data.pokemon[species]
  return def and def.spriteFront
end

-- the point (in the sprite's pixels) a slot sits at
function M.anchor(box, slot)
  local cx = (box.x0 + box.x1) / 2
  local w, h = box.x1 - box.x0, box.y1 - box.y0
  local top = box.y0
  if slot == 0 then return box.x0 + w * 0.22, top + h * 0.06 end
  if slot == 1 then return box.x1 - w * 0.22, top + h * 0.06 end
  if slot == 2 then return cx, top + h * 0.02 end
  if slot == 3 then return cx, top + h * 0.28 end
  if slot == 4 then return cx, top + h * 0.40 end
  if slot == 5 then return cx, top + h * 0.58 end
  if slot == 6 then return cx, top + h * 0.75 end
  if slot == 7 then return box.x0 + w * 0.05, top + h * 0.62 end
  return box.x1 - w * 0.05, top + h * 0.62
end

-- draw `species` at (x, y) = the sprite's bottom centre, scaled, wearing
-- `outfit` ({ [slot] = { id = prop } })
function M.drawMon(data, species, outfit, x, y, scale, opts)
  if not lg then return end
  scale = scale or 1
  local rec = data and data.constants and data.constants.gen5Musical
  local path = M.front(data, species)
  local img = M.image(path)
  local box = M.box(path)
  local w, h = 96, 96
  if img then w, h = img:getDimensions() end
  box = box or { x0 = 16, y0 = 16, x1 = w - 16, y1 = h - 4, w = w, h = h }
  local ox = x - (box.x0 + box.x1) / 2 * scale
  local oy = y - (box.y1 + 1) * scale
  local function prop(slot, item)
    local p = rec and rec.props and rec.props[item.id]
    local pic = rec and rec.images and M.image(rec.images[item.id])
    if not (p and pic) then return end
    local ax, ay = M.anchor(box, slot)
    local pw, ph = pic:getDimensions()
    local flip = (slot == 1 or slot == 8) and -1 or 1
    -- the prop's own offset (y up on the DS stage, so it is subtracted)
    local px = ox + (ax + (p.dx or 0) * flip) * scale
    local py = oy + (ay - (p.dy or 0)) * scale
    lg.draw(pic, px, py, 0, scale * flip * 0.75, scale * 0.75, pw / 2, ph / 2)
  end
  -- what goes behind (capes and wings, mask bit 7) first
  for slot, item in pairs(outfit or {}) do
    local p = rec and rec.props and rec.props[item.id]
    if p and (p.mask or 0) >= 0x80 then prop(slot, item) end
  end
  if img then
    lg.setColor(1, 1, 1, (opts and opts.alpha) or 1)
    lg.draw(img, ox, oy, 0, scale, scale)
  end
  for slot = 0, 8 do
    local item = outfit and outfit[slot]
    local p = item and rec and rec.props and rec.props[item.id]
    if p and (p.mask or 0) < 0x80 then prop(slot, item) end
  end
end

-- a prop's picture on its own, centred in a cell
function M.drawProp(data, id, cx, cy, size)
  local rec = data and data.constants and data.constants.gen5Musical
  local pic = rec and rec.images and M.image(rec.images[id])
  if not (pic and lg) then return false end
  local pw, ph = pic:getDimensions()
  local s = (size or 24) / math.max(pw, ph)
  lg.draw(pic, cx, cy, 0, s, s, pw / 2, ph / 2)
  return true
end

return M
