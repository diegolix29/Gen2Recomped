-- spanish_ui: a translation of the game into Espanol.
--
-- Nothing here is translated yet.  Every table under lang/ starts with
-- empty strings; fill one in and it takes effect on the next boot, and
-- anything still empty keeps rendering in English.  That means a
-- half-finished translation is always playable, so you can ship early and
-- fill the long tail in later.
--
-- Read TRANSLATING.md before the first edit; the font is the part people
-- get wrong.
return function(mod)
  -- mod:read is the supported way into your own directory; the catalogs are
  -- plain Lua tables, so read and run them rather than require()ing them.
  local function catalog(name)
    local rel = "lang/" .. name .. ".lua"
    local body = mod:read(rel)
    if not body then return {} end
    local chunk, err = loadstring(body, rel)
    if not chunk then
      mod.log:warn("%s has a syntax error: %s", rel, tostring(err))
      return {}
    end
    local ok, table_ = pcall(chunk)
    if not ok or type(table_) ~= "table" then
      mod.log:warn("%s did not return a table: %s", rel, tostring(table_))
      return {}
    end
    return table_
  end

  -- An empty value means "not translated yet", never "translate to blank".
  local function each(name, apply)
    local n = 0
    for key, value in pairs(catalog(name)) do
      if type(value) == "string" and value ~= "" then
        apply(key, value)
        n = n + 1
      end
    end
    return n
  end

  -- ---- glyphs -------------------------------------------------------
  -- Register the sheet BEFORE anything asks for a glyph on it.  base is
  -- the first code the page owns; 0x100 and up is free space above the
  -- vanilla pages, so a new alphabet never collides with them.
  for id, page in pairs(catalog("font")) do
    mod.content.font:register(id, page)
  end
  -- charmap: which byte sequence draws which code
  for seq, code in pairs(catalog("charmap")) do
    mod.content.font:register("charmap:" .. seq, { seq = seq, code = code })
  end

  -- ---- text ---------------------------------------------------------
  local counts = {}
  counts.dialogue = each("dialogue", function(id, value)
    mod.content.text:override(id, value)
  end)
  counts.strings = each("strings", function(source, value)
    mod.content.strings:override(source, value)
  end)
  counts.species = each("species_names", function(id, value)
    mod.content.pokemon:patch(id, { name = value })
  end)
  counts.moves = each("move_names", function(id, value)
    mod.content.moves:patch(id, { name = value })
  end)
  counts.items = each("item_names", function(id, value)
    mod.content.items:patch(id, { name = value })
  end)
  counts.trainers = each("trainer_names", function(id, value)
    mod.content.trainers:patch(id, { name = value })
  end)
  counts.statuses = each("status_labels", function(id, value)
    mod.content.statuses:patch(id, { label = value })
  end)

  -- ---- name entry ---------------------------------------------------
  -- The naming screen's letter grid.  Leave lang/naming.lua returning nil
  -- to keep the English alphabet.
  local grid = catalog("naming")
  if grid.upper then
    -- Only offer the accented cells when the running cartridge can actually
    -- draw them.  A Spanish ROM has Ñ and the accented vowels in its font
    -- and the manifest maps them; an English one does not, and an
    -- unmappable cell renders blank -- a naming screen with six empty keys
    -- is worse than an English one.  So check the charmap and fall back.
    local function drawable(cells, ctx)
      local font = ((ctx.game or {}).data or {}).font
      local charmap = font and font.charmap
      if not charmap then return false end
      local have = {}
      for _, entry in ipairs(charmap) do have[entry.seq] = true end
      for _, row in ipairs(cells) do
        for _, cell in ipairs(row) do
          -- Only the non-ASCII cells are at risk; A-Z and punctuation are
          -- on every page.
          if cell:byte(1) and cell:byte(1) > 127 and not have[cell] then
            return false
          end
        end
      end
      return true
    end
    local warned = false
    mod.hooks:on("ui.naming.grid", function(base, ctx)
      local want = ctx.lower and grid.lower or grid.upper
      if not want then return base end
      if not drawable(want, ctx) then
        if not warned then
          warned = true
          mod.log:info("naming grid: this ROM has no accented glyphs, "
            .. "keeping the English alphabet")
        end
        return base
      end
      return want
    end)
  end

  mod.events:on("game.ready", function()
    local total = 0
    for _, n in pairs(counts) do total = total + n end
    mod.log:info("Espanol: %d strings translated", total)
  end)
end
