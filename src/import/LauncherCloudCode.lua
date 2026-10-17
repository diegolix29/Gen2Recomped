-- THE SIGN-IN CODE POPUP (cloud saves, docs/cloud-saves.md).
--
-- Google Drive and OneDrive sign in with a short code the player types on
-- the provider's website. Instead of a one-line notice, the launcher shows
-- the code in a popup over everything: big and bold, a COPY button beside
-- it, the steps, and an OPEN WEBSITE button. The website is not opened on
-- its own any more, so the player can copy the code first.
--
-- The popup is up while a device-code sign-in waits (self._cloudFlow with a
-- device flow). It closes itself when LauncherSidebar's poll sees the
-- sign-in finish or fail; CANCEL (or Escape) stops the sign-in.
--
-- Installed by LauncherSidebar after its own wrappers, so it draws last and
-- sees every press first.

local Strings = require("src.core.Strings")

local CloudCode = {}

function CloudCode.install(RI)
  local U = RI._ui
  local col, inside, fillGradRounded = U.col, U.inside, U.fillGradRounded
  local function PAL() return RI.palette() end

  -- big faces, made once per size
  local fonts = {}
  local function font(px)
    px = math.max(8, math.floor(px + 0.5))
    if not fonts[px] then
      local path = require("src.translation.Service").launcherFont
      fonts[px] = path and love.graphics.newFont(path, px) or love.graphics.newFont(px)
    end
    return fonts[px]
  end

  -- bold by over-printing, heavier for bigger text
  local function bold(text, x, y, w, align, weight)
    local g = love.graphics
    for i = 0, weight do g.printf(text, x + i * 0.6, y, w, align) end
  end

  function RI:_ccVisible()
    local c = self._cloudFlow
    return c and c.flow and c.flow.kind == "device" and c.flow.code and true or false
  end

  function RI:_ccCopy()
    local c = self._cloudFlow
    if not c then return end
    pcall(love.system.setClipboardText, c.flow.code)
    c.copiedAt = love.timer and love.timer.getTime() or 0
  end

  function RI:_ccOpen()
    local c = self._cloudFlow
    if not c then return end
    pcall(love.system.openURL, c.flow.url)
    c.opened = true
  end

  function RI:_ccCancel()
    if self._cloudFlow then self:_sbCloudSignIn() end -- pressing it while waiting cancels
  end

  -- a filled button; returns its rect
  local function button(self, x, y, w, h, label, kind)
    local s, P, g = self._s or 1, PAL(), love.graphics
    local r = { x = x, y = y, width = w, height = h, pinned = true }
    local hot = self:_hover(r)
    local rad = 10 * s
    if kind == "go" then
      fillGradRounded(x, y, w, h, rad, P.playTop, P.playBot, hot and 1 or 0.88, hot and 1 or 0.88)
      col(P.playInk)
    elseif kind == "copy" then
      col(P.gold, hot and 1 or 0.88)
      g.rectangle("fill", x, y, w, h, rad, rad)
      col(P.playInk)
    else
      col(P.disabled, hot and 0.55 or 0.35)
      g.rectangle("fill", x, y, w, h, rad, rad)
      col(P.ink)
    end
    local f = font(17 * s)
    g.setFont(f)
    bold(Strings(label), x, y + (h - f:getHeight()) / 2, w, "center", 1)
    return r
  end

  local origDraw = RI.draw
  RI.draw = function(self, ...)
    local r = origDraw(self, ...)
    if not self:_ccVisible() then self._cc = nil; return r end
    local c = self._cloudFlow
    local s, P, g = self._s or 1, PAL(), love.graphics
    local W, H = g.getDimensions()
    local now = love.timer and love.timer.getTime() or 0
    g.push("all")
    g.origin()
    g.setScissor()
    col(P.bgBot, 0.78)
    g.rectangle("fill", 0, 0, W, H)

    local pad = 26 * s
    local dw = math.min(W - 24 * s, 620 * s)
    local inner = dw - 2 * pad
    local titleF, stepF, codeF, smallF = font(26 * s), font(16 * s), font(64 * s), font(13 * s)
    -- the code shrinks to fit a narrow phone screen next to its COPY button
    local copyW, gap = 120 * s, 14 * s
    while codeF:getWidth(c.flow.code) > inner - copyW - gap - 20 * s and codeF:getHeight() > 24 do
      codeF = font(codeF:getHeight() * 0.9)
    end
    local steps = {
      "1.  Press COPY to copy your code.",
      "2.  Press OPEN WEBSITE and sign in to your " .. (c.name == "OneDrive" and "Microsoft" or "Google") .. " account.",
      "3.  Paste the code there and allow access to " .. c.name .. ".",
      "4.  Come back here. This closes by itself once you're in.",
    }
    g.setFont(stepF)
    local stepsH = 0
    for i, t in ipairs(steps) do
      steps[i] = Strings(t)
      local _, lines = stepF:getWrap(steps[i], inner)
      stepsH = stepsH + #lines * stepF:getHeight() + 6 * s
    end
    local codeBoxH = codeF:getHeight() + 28 * s
    local btnH = 50 * s
    local dh = pad + titleF:getHeight() + 14 * s + stepsH + 16 * s + codeBoxH + 10 * s
             + smallF:getHeight() + 20 * s + btnH + 14 * s + smallF:getHeight() + pad
    local dx, dy = (W - dw) / 2, math.max(8 * s, (H - dh) / 2)
    local rr = 16 * s

    fillGradRounded(dx, dy, dw, dh, rr, P.slotBg or P.bgTop, P.slotBg or P.bgBot, 0.97, 0.97)
    g.setLineWidth(math.max(1, 1.5 * s))
    col(P.gold, 0.7)
    g.rectangle("line", dx, dy, dw, dh, rr, rr)

    local x, y = dx + pad, dy + pad
    g.setFont(titleF)
    col(P.ink)
    bold(Strings("Sign in to ") .. c.name, x, y, inner, "left", 1)
    y = y + titleF:getHeight() + 14 * s

    g.setFont(stepF)
    col(P.detail)
    for _, t in ipairs(steps) do
      g.printf(t, x, y, inner, "left")
      local _, lines = stepF:getWrap(t, inner)
      y = y + #lines * stepF:getHeight() + 6 * s
    end
    y = y + 16 * s

    -- THE CODE, big and bold, with COPY beside it
    local boxW = inner - copyW - gap
    col(P.bgBot, 0.85)
    g.rectangle("fill", x, y, boxW, codeBoxH, 12 * s, 12 * s)
    g.setLineWidth(math.max(1, 2 * s))
    col(P.gold, 0.9)
    g.rectangle("line", x, y, boxW, codeBoxH, 12 * s, 12 * s)
    g.setFont(codeF)
    col(P.white)
    bold(c.flow.code, x, y + 14 * s, boxW, "center", 3)
    local copied = c.copiedAt and now - c.copiedAt < 2
    local copyR = button(self, x + boxW + gap, y, copyW, codeBoxH, copied and "COPIED!" or "COPY", "copy")
    y = y + codeBoxH + 10 * s

    g.setFont(smallF)
    col(P.detail, 0.85)
    g.printf(c.flow.url, x, y, inner, "center")
    y = y + smallF:getHeight() + 20 * s

    local bw = (inner - gap) / 2
    local openR = button(self, x, y, bw, btnH, c.opened and "OPEN AGAIN" or "OPEN WEBSITE", "go")
    local cancelR = button(self, x + bw + gap, y, bw, btnH, "CANCEL", "cancel")
    y = y + btnH + 14 * s

    g.setFont(smallF)
    col(P.detail, 0.75)
    local dots = ("."):rep(math.floor(now * 2) % 4)
    g.printf(Strings("Waiting for you to finish on the website") .. dots, x, y, inner, "center")

    g.pop()
    self._cc = { copy = copyR, open = openR, cancel = cancelR }
    return r
  end

  -- the popup takes every press while it is up
  local origPress = RI.mousepressed
  RI.mousepressed = function(self, x, y, button, ...)
    if not self:_ccVisible() then return origPress(self, x, y, button, ...) end
    local cc = self._cc
    if button ~= 1 or not cc then return end
    if inside(cc.copy, x, y) then self:_ccCopy()
    elseif inside(cc.open, x, y) then self:_ccOpen()
    elseif inside(cc.cancel, x, y) then self:_ccCancel() end
  end

  local origKey = RI.keypressed
  RI.keypressed = function(self, key, ...)
    if not self:_ccVisible() then return origKey(self, key, ...) end
    local ctrl = love.keyboard and (love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui"))
    if key == "escape" then self:_ccCancel()
    elseif key == "c" and ctrl then self:_ccCopy()
    elseif key == "return" or key == "kpenter" then self:_ccOpen() end
  end

  if RI.wheelmoved then
    local origWheel = RI.wheelmoved
    RI.wheelmoved = function(self, ...)
      if self:_ccVisible() then return end
      return origWheel(self, ...)
    end
  end
  if RI.textinput then
    local origText = RI.textinput
    RI.textinput = function(self, ...)
      if self:_ccVisible() then return end
      return origText(self, ...)
    end
  end
end

return CloudCode
