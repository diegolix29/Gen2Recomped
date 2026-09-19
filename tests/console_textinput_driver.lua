-- Regression: developer-console characters must follow LOVE's text-input
-- events, which preserves Caps Lock, keyboard layouts and pasted text.
return function(game)
  local U = require("tests.drivers.util")
  U.freshSave(game)
  U.teleport(game, "MAP_G03_N00", 10, 10, "down")
  game:keypressed("`")
  local console = game.stack:top()
  assert(console and console.onTextInput, "developer console did not open")
  assert(love.keyboard.hasTextInput and love.keyboard.hasTextInput(),
    "developer console did not arm native text input")
  assert(game.textinput, "Game does not forward text input to overlays")
  game:textinput("READY_SET")
  assert(console.buffer == "READY_SET",
    "developer console lost capital letters or underscore text")
  local oldIsDown = love.keyboard.isDown
  love.keyboard.isDown = function(key) return key == "lshift" end
  console:onKeyPressed("-")
  love.keyboard.isDown = oldIsDown
  assert(console.buffer:sub(-1) == "_", "shifted hyphen did not produce underscore")
  console:onTextInput("_")
  assert(console.buffer == "READY_SET_",
    "native underscore duplicated the console fallback")
  local oldClipboard = love.system.getClipboardText
  local oldIsDown = love.keyboard.isDown
  love.system.getClipboardText = function() return " warp MAP_G03_N00 10 10 " end
  love.keyboard.isDown = function(key) return key == "lctrl" end
  console:onKeyPressed("v")
  love.system.getClipboardText = oldClipboard
  love.keyboard.isDown = oldIsDown
  assert(console.buffer:sub(-22) == " warp MAP_G03_N00 10 10 ",
    "Ctrl+V did not paste clipboard text into the console")
  console:exec("  help  ")
  assert(console.lines[#console.lines] == "anything else = lua",
    "console did not trim whitespace around a pasted command")
  U.log("PASS console accepts native text input")
  love.event.quit(0)
end
