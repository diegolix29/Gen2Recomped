-- PLAY OVER THE INTERNET: what to do when only this Wi-Fi can reach a world.
--
--   InternetHelp.open(game, { role = "host" | "join" | "info" })
--
-- Opened by WorldMenu when a hosted world's router opening failed (no UPnP,
-- no forwarded port, no Link Hub: only the LAN can join), when a join could
-- not reach its host, and from the INTERNET HELP rows.  Three fixes, each a
-- few short steps (a GB screen is 160x144, so a step is a few lines and
-- NEXT goes on):
--
--   TAILSCALE    a free VPN app on every device; it gets through any router
--                or carrier.  This device's Tailscale address is found here
--                (Util.tailscaleIP) and one press writes it to MY ADDRESS
--                (save.options.online.manualAddress), so the next world
--                code carries it.
--   OPEN A PORT  the router's own page: forward UDP <port> to this device.
--   LINK HUB     a hub on a server everyone reaches (tools/online-hub),
--                set in OPTIONS > ONLINE > LINK HUB.

local WorldUi = require("src.ui.online.WorldUi")

local InternetHelp = {}
InternetHelp.__index = InternetHelp
InternetHelp.isOpaque = true
InternetHelp.isWorldUi = true

local function world() return require("src.online.world.OnlineWorld") end

local function util()
  local ok, Util = pcall(require, "src.online.net.Util")
  return ok and Util or nil
end

local INTROS = {
  host = { title = "ONLY YOUR WI-FI",
           text = "Your router didn't open a port, so friends on other networks can't "
             .. "reach your world. Friends on your Wi-Fi still can." },
  join = { title = "CAN'T REACH IT",
           text = "The host's router keeps the internet out. The HOST needs a fix "
             .. "(with Tailscale, you install it too)." },
  info = { title = "PLAY ONLINE",
           text = "On one Wi-Fi, worlds just show up. Friends elsewhere need the "
             .. "host's router open, or a fix." },
}

function InternetHelp.open(game, opts)
  local self = setmetatable({}, InternetHelp)
  self.game = game
  self.opts = opts or {}
  self.role = INTROS[self.opts.role] and self.opts.role or "info"
  self.width, self.height = WorldUi.surface()
  self.style = WorldUi.style(game)
  self.section, self.step, self.index = nil, 1, 1
  self:scan()
  game.stack:push(self)
  return self
end

function InternetHelp:uiSize() return self.width, self.height end

function InternetHelp:close()
  if self.game.stack:top() == self then self.game.stack:pop() end
end

-- this device's addresses and the port worlds are hosted on
function InternetHelp:scan()
  local Util = util()
  self.tailscale = Util and Util.tailscaleIP and Util.tailscaleIP() or nil
  self.lanIp = Util and Util.lanIP and Util.lanIP() or nil
  self.port = 7777
  local okL, LinkState = pcall(require, "src.link.LinkState")
  if okL and type(LinkState) == "table" and LinkState.settings then
    local okS, s = pcall(LinkState.settings, self.game)
    if okS and type(s) == "table" then
      self.port = tonumber(s.port) or self.port
      self.myAddress = s.manualAddress
    end
  end
end

-- ------------------------------------------------------------ content

function InternetHelp:sections()
  local lan = self.lanIp or "this device"
  return {
    tailscale = {
      title = "TAILSCALE",
      steps = {
        "Easiest, free, no router settings. Install the Tailscale app on EVERY "
          .. "device that plays: phones, tablets, PCs.",
        "Sign in to the same Tailscale account on all of them, or have the host "
          .. "share their device with a friend's account in the app.",
        "Turn Tailscale on. Phones allow one VPN at a time, so switch off any other VPN.",
        "HOST: use your Tailscale address below, then host the world again. "
          .. "FRIENDS: enter the new code. Nothing else to set.",
      },
      final = "tailscale",
    },
    port = {
      title = "OPEN A PORT",
      steps = {
        "Open your router's page in a browser: usually 192.168.1.1 or 192.168.0.1. "
          .. "The login is often on a sticker on the router.",
        ("Find PORT FORWARDING (or Virtual Server / NAT). Add UDP %d to %s."):format(self.port, lan),
        "Reserve that address for this device (DHCP reservation), or the rule "
          .. "breaks when it reconnects. Then host the world again.",
        "Still nothing? If the router's WAN address differs from whatismyip.com, "
          .. "your provider shares it and no rule can work. Use Tailscale.",
      },
    },
    hub = {
      title = "LINK HUB",
      steps = {
        "A Link Hub on a server everyone can reach does what the router can't, "
          .. "for a whole group, always on.",
        "Run tools/online-hub on a small cloud server (a VPS). Open TCP+UDP 7778 "
          .. "and UDP 7779 in its firewall.",
        "Everyone sets OPTIONS > ONLINE > LINK HUB to the server's address. "
          .. "Its README has the details.",
      },
    },
  }
end

function InternetHelp:rows()
  if not self.section then
    return {
      { label = "SHOW FIXES", go = "menu" },
      { label = "BACK", back = true },
    }
  end
  if self.section == "menu" then
    return {
      { label = "TAILSCALE", value = "EASY", go = "tailscale" },
      { label = "OPEN A PORT", go = "port" },
      { label = "LINK HUB", value = "VPS", go = "hub" },
      { label = "BACK", back = true },
    }
  end
  local sec = self:sections()[self.section]
  local rows = {}
  if self.step < #sec.steps then
    rows[#rows + 1] = { label = "NEXT", next = true }
  elseif sec.final == "tailscale" then
    if self.tailscale then
      local using = self.myAddress == self.tailscale
      rows[#rows + 1] = { label = using and "IN USE" or "USE", value = self.tailscale,
                          act = "useTailscale", disabled = using }
    else
      rows[#rows + 1] = { label = "NOT FOUND, RECHECK", act = "rescan" }
    end
  end
  rows[#rows + 1] = { label = "BACK", back = true }
  return rows
end

function InternetHelp:text()
  if not self.section then
    local intro = INTROS[self.role]
    return intro.title, intro.text
  end
  if self.section == "menu" then
    return "PICK A FIX", "Tailscale needs no router settings."
  end
  local sec = self:sections()[self.section]
  return ("%s %d/%d"):format(sec.title, self.step, #sec.steps), sec.steps[self.step]
end

-- ------------------------------------------------------------ actions

function InternetHelp:useTailscale()
  local ip = self.tailscale
  if not ip then return end
  local save = self.game and self.game.save
  if not save then self.notice = "No save to keep it in." return end
  save.options = save.options or {}
  if type(save.options.online) ~= "table" then save.options.online = {} end
  save.options.online.manualAddress = ip
  if self.game.writeOptions then pcall(self.game.writeOptions, self.game) end
  self.myAddress = ip
  local s = world().current()
  if s and s.host then
    self.notice = "Saved. Close this world and host it again for a code with it."
  else
    self.notice = "Saved. Host a world: its code now carries this address."
  end
end

function InternetHelp:back()
  self.notice = nil
  if not self.section then self:close() return end
  if self.section == "menu" then self.section, self.index = nil, 1 return end
  if self.step > 1 then
    self.step = self.step - 1
  else
    self.section, self.index = "menu", 1
  end
end

function InternetHelp:activate(row)
  if row.back then self:back() return end
  self.notice = nil
  if row.go then
    self.section, self.step, self.index = row.go, 1, 1
  elseif row.next then
    self.step, self.index = self.step + 1, 1
  elseif row.act == "useTailscale" then
    self:useTailscale()
  elseif row.act == "rescan" then
    self:scan()
    if not self.tailscale then self.notice = "No Tailscale address. Is the app on and signed in?" end
  end
end

function InternetHelp:update(dt)
  world().tick(dt)
  local input = self.game.input
  local rows = self:rows()
  if self.index > #rows then self.index = #rows end
  -- never rest on a greyed row (IN USE)
  for _ = 1, #rows do
    if not (rows[self.index] and rows[self.index].disabled) then break end
    self.index = self.index % #rows + 1
  end
  self.index = WorldUi.nav(self.game, self.index, rows)
  if not input then return end
  local row = rows[self.index]
  if input:wasPressed("a") and row and not row.disabled then
    WorldUi.sound(self.game, "Select")
    self:activate(row)
  elseif input:wasPressed("b") then
    self:back()
  end
end

function InternetHelp:onKeyPressed(key)
  local input = self.game and self.game.input
  if input and input.keypressed then input:keypressed(key) end
end

-- ------------------------------------------------------------ draw

function InternetHelp:draw()
  local st = self.style
  local W, H = self.width, self.height
  st:clear(W, H)
  local title, body = self:text()
  local rows = self:rows()
  local lh = st:lineHeight()
  local listH = (#rows) * (lh + 2) + 10
  -- a notice (saved / not found) takes the step's place: a GB screen has no
  -- room for both
  local text = title .. "\n" .. (self.notice or body)
  WorldUi.drawText(st, 4, 4, W - 8, text)
  WorldUi.drawList(st, 4, H - listH - 4, W - 8, rows, self.index)
end

return InternetHelp
