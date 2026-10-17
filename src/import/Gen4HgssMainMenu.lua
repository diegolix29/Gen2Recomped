-- main_menu.c: HGSS uses 23-tile windows on the touch screen, not
-- Platinum's 26-tile, two-tile-high options. Link-only services stay hidden.
local M = {
  WINFRAME='/a/0/3/8', system=0, field=1, palette=25,
  FONT='/a/0/1/6', FONT_PALETTE=7,
  MYSTERY='/a/1/1/3', arrowTiles=47, arrowCells=46, arrowAnim=45, arrowPalette=44,
  BORDER_CYCLE={{1,28,20}},
}
for _,c in ipairs(require('src.import.Gen4MainMenuArt').BORDER_CYCLE) do
  M.BORDER_CYCLE[#M.BORDER_CYCLE+1]=c
end
function M.images(rom) return require('src.import.Gen4MainMenuArt').images(rom,M) end
function M.ink(rom) return require('src.import.Gen4MainMenuArt').data(rom,M) end
function M.words(stringAt, options)
  local function word(i) return (stringAt(442,i) or ''):gsub('{[^}]+}','') end
  return {
    hgss=true, options=options,
    layout={optionX=3,optionWidth=23,firstY=1,gap=2,lineTiles=2,
      linePixels=16,margin=32,arrowX=236,arrowUp=20,arrowDown=172},
    rows={{id='continue',label=word(0),lines=5},
      {id='newGame',label=word(1),lines=2},
      {id='options',label=options and options.title or 'OPTION',lines=2}},
    continueRows={{label=word(13),value='playerName'},
      {label=word(14),value='playTime'}, {label=word(16),value='badgeCount'},
      {label=word(15),value='ownedCount',needsPokedex=true}},
  }
end
return M
