-- GIF89a decoder for Reloded HD frames. One file at a time, no Python.
local M = {}

local function u16(s, p)
  local a, b = s:byte(p, p + 1)
  if not b then return 0, p end
  return a + b * 256, p + 2
end

local function palette(s, p, count)
  local pal = {}
  for i = 0, count - 1 do
    local r, g, b = s:byte(p, p + 2)
    pal[i] = { (r or 0) / 255, (g or 0) / 255, (b or 0) / 255, 1 }
    p = p + 3
  end
  return pal, p
end

local function lzw(minSize, data, pixelCount)
  local clear = 2 ^ minSize
  local stop = clear + 1
  local codeSize = minSize + 1
  local nextCode = stop + 1
  local dict = {}
  local function reset()
    dict = {}
    for i = 0, clear - 1 do dict[i] = { i } end
    codeSize = minSize + 1
    nextCode = stop + 1
  end
  reset()
  local out = {}
  local n = 0
  local acc, bits, i = 0, 0, 1
  local function readCode()
    while bits < codeSize and i <= #data do
      acc = acc + data:byte(i) * (2 ^ bits)
      bits = bits + 8
      i = i + 1
    end
    if bits < codeSize then return nil end
    local mask = 2 ^ codeSize - 1
    local code = acc % (mask + 1)
    acc = math.floor(acc / (mask + 1))
    bits = bits - codeSize
    return code
  end
  local prev
  while n < pixelCount do
    local code = readCode()
    if not code or code == stop then break end
    if code == clear then
      reset()
      prev = nil
    else
      local entry = dict[code]
      if not entry then
        if prev and code == nextCode then
          entry = {}
          for k = 1, #prev do entry[k] = prev[k] end
          entry[#entry + 1] = prev[1]
        else
          break
        end
      end
      for k = 1, #entry do
        n = n + 1
        out[n] = entry[k]
        if n >= pixelCount then break end
      end
      if prev and nextCode < 4096 then
        local neu = {}
        for k = 1, #prev do neu[k] = prev[k] end
        neu[#neu + 1] = entry[1]
        dict[nextCode] = neu
        nextCode = nextCode + 1
        if nextCode == 2 ^ codeSize and codeSize < 12 then
          codeSize = codeSize + 1
        end
      end
      prev = entry
    end
  end
  return out
end

local function deinterlace(src, w, h)
  local dest = {}
  local rows = { { 0, 8 }, { 4, 8 }, { 2, 4 }, { 1, 2 } }
  local i = 1
  for _, pass in ipairs(rows) do
    local y = pass[1]
    while y < h do
      for x = 0, w - 1 do
        dest[y * w + x + 1] = src[i]
        i = i + 1
      end
      y = y + pass[2]
    end
  end
  return dest
end

local function newCanvas(w, h)
  local id = love.image.newImageData(w, h)
  id:mapPixel(function() return 0, 0, 0, 0 end)
  return id
end

local function copyId(src)
  local w, h = src:getWidth(), src:getHeight()
  local dest = love.image.newImageData(w, h)
  dest:paste(src, 0, 0, 0, 0, w, h)
  return dest
end

function M.decode(bytes)
  if type(bytes) ~= "string" or #bytes < 13 or bytes:sub(1, 3) ~= "GIF" then
    return nil, "not a gif"
  end
  local p = 7
  local width, p1 = u16(bytes, p)
  local height, p2 = u16(bytes, p1)
  p = p2
  local packed, bg = bytes:byte(p, p + 1)
  p = p + 3
  local gct
  if packed and packed >= 128 then
    gct, p = palette(bytes, p, 2 ^ ((packed % 8) + 1))
  end
  local canvas = newCanvas(width, height)
  local backup
  local delay, trans, disposal = 10, nil, 0
  local frames = {}
  while p <= #bytes do
    local tag = bytes:byte(p)
    p = p + 1
    if tag == 0x3B then
      break
    elseif tag == 0x21 then
      local label = bytes:byte(p)
      p = p + 1
      if label == 0xF9 then
        p = p + 1
        local gpacked = bytes:byte(p)
        local d, pDelay = u16(bytes, p + 1)
        delay = math.max(1, d)
        trans = bytes:byte(p + 3)
        disposal = math.floor((gpacked or 0) / 4) % 8
        if (gpacked or 0) % 2 == 0 then trans = nil end
        p = pDelay + 3
        if bytes:byte(p) == 0 then p = p + 1 end
      else
        local size = bytes:byte(p) or 0
        p = p + 1
        while size and size > 0 do
          p = p + size
          size = bytes:byte(p) or 0
          p = p + 1
        end
      end
    elseif tag == 0x2C then
      local left, pL = u16(bytes, p)
      local top, pT = u16(bytes, pL)
      local iw, pW = u16(bytes, pT)
      local ih, pH = u16(bytes, pW)
      p = pH
      local ipacked = bytes:byte(p) or 0
      p = p + 1
      local lct = gct
      if ipacked >= 128 then
        lct, p = palette(bytes, p, 2 ^ ((ipacked % 8) + 1))
      end
      local minSize = bytes:byte(p) or 2
      p = p + 1
      local blob, size = {}, bytes:byte(p) or 0
      p = p + 1
      while size and size > 0 do
        blob[#blob + 1] = bytes:sub(p, p + size - 1)
        p = p + size
        size = bytes:byte(p) or 0
        p = p + 1
      end
      local indices = lzw(minSize, table.concat(blob), iw * ih)
      if ipacked % 64 >= 32 then indices = deinterlace(indices, iw, ih) end
      if disposal == 3 then backup = copyId(canvas) end
      if disposal == 2 then
        for y = 0, ih - 1 do
          for x = 0, iw - 1 do
            canvas:setPixel(left + x, top + y, 0, 0, 0, 0)
          end
        end
      end
      for y = 0, ih - 1 do
        for x = 0, iw - 1 do
          local idx = indices[y * iw + x + 1]
          if idx and not (trans and idx == trans) and lct and lct[idx] then
            local c = lct[idx]
            canvas:setPixel(left + x, top + y, c[1], c[2], c[3], c[4])
          end
        end
      end
      frames[#frames + 1] = { image = copyId(canvas), duration = delay * 10 }
      if disposal == 3 and backup then
        canvas = backup
        backup = nil
      elseif disposal == 2 then
        -- already cleared the frame rect before draw; after snapshot leave canvas as-is
      end
    else
      break
    end
  end
  if #frames < 1 then
    frames[1] = { image = canvas, duration = 100 }
  end
  return { width = width, height = height, frames = frames }
end

local function scaleFrame(src, scale)
  local sw, sh = src:getWidth(), src:getHeight()
  local dw = math.max(1, math.floor(sw * scale + 0.5))
  local dh = math.max(1, math.floor(sh * scale + 0.5))
  if dw == sw and dh == sh then return src, dw, dh end
  local dest = love.image.newImageData(dw, dh)
  for y = 0, dh - 1 do
    local sy = math.min(sh - 1, math.floor(y * sh / dh))
    for x = 0, dw - 1 do
      local sx = math.min(sw - 1, math.floor(x * sw / dw))
      dest:setPixel(x, y, src:getPixel(sx, sy))
    end
  end
  return dest, dw, dh
end

function M.packSheet(decoded, scale)
  if type(decoded) ~= "table" or type(decoded.frames) ~= "table" or not decoded.frames[1] then
    return nil, "no frames"
  end
  scale = tonumber(scale) or 0.60
  local frames = decoded.frames
  local first, fw, fh = scaleFrame(frames[1].image, scale)
  local n = #frames
  local maxTex = 8192
  local maxCols = math.min(n, math.floor(maxTex / fw))
  local cols = math.max(1, math.min(maxCols, n))
  local rows = math.ceil(n / cols)
  while cols > 1 and rows * fh > maxTex do
    cols = cols - 1
    rows = math.ceil(n / cols)
  end
  local sheet = love.image.newImageData(cols * fw, rows * fh)
  local durations = {}
  for i = 1, n do
    local img = i == 1 and first or scaleFrame(frames[i].image, scale)
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    sheet:paste(img, col * fw, row * fh, 0, 0, fw, fh)
    durations[i] = math.max(1, tonumber(frames[i].duration) or 100)
  end
  local encoded = sheet:encode("png")
  local bytes = encoded and encoded.getString and encoded:getString() or nil
  if type(bytes) ~= "string" or #bytes == 0 then return nil, "png encode failed" end
  return {
    bytes = bytes,
    width = fw,
    height = fh,
    columns = cols,
    frames = n,
    durations = durations,
  }
end

return M
