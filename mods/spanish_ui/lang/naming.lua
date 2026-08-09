-- The naming screen's letter grid.  Return an empty table to keep the
-- English alphabet.
--
-- Each entry is a row of cells; a cell is whatever sequence your charmap
-- maps, so a multi-byte character is one cell.  The row holding a single
-- "lower case" / "UPPER CASE" cell is the case switch, and the cell
-- spelled "ED" is the confirm.
--
-- The screen is 160x144 and NamingScreen draws cell `c` of row `r` at
-- (c * 16, 32 + r * 16), so the grid is capped at **9 columns and 6 rows**:
-- a 10th column lands at x=160 and a 7th row at y=144, both off screen.
-- That leaves 44 usable cells, exactly what vanilla uses, so Spanish
-- letters have to displace something rather than being added.
--
-- What gives way is vanilla's `× ( ) : ; [ ]` row.  Those are legal in a
-- Gen-1 nickname but nobody reaches for them, whereas Ñ is not optional in
-- Spanish -- and here it sits in its alphabetical place after N, which is
-- where a Spanish speaker will look for it.  Space, <PK> and <MN> are kept.
--
-- These glyphs exist in the Spanish cartridge's font ($CA Ñ, $BF Á, $C7 É,
-- $C9 Í, $CC Ó, $CE Ú, $C2 Ü and their lowercase).  On an English ROM they
-- do not, so main.lua checks the running game's charmap first and keeps the
-- English grid rather than drawing blank cells.
return {
  upper = {
    { "A", "B", "C", "D", "E", "F", "G", "H", "I" },
    { "J", "K", "L", "M", "N", "Ñ", "O", "P", "Q" },
    { "R", "S", "T", "U", "V", "W", "X", "Y", "Z" },
    { "Á", "É", "Í", "Ó", "Ú", "Ü", " ", "<PK>", "<MN>" },
    { "-", "?", "!", "♂", "♀", "/", ".", ",", "ED" },
    { "lower case" },
  },
  lower = {
    { "a", "b", "c", "d", "e", "f", "g", "h", "i" },
    { "j", "k", "l", "m", "n", "ñ", "o", "p", "q" },
    { "r", "s", "t", "u", "v", "w", "x", "y", "z" },
    { "á", "é", "í", "ó", "ú", "ü", " ", "<PK>", "<MN>" },
    { "-", "?", "!", "♂", "♀", "/", ".", ",", "ED" },
    { "UPPER CASE" },
  },
}
