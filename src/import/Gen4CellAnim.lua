-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- NANR: which cell a sprite shows on which frame, and for how long.
--
-- `Gen4Cells` reads an NCER and says what one cell LOOKS like. It says nothing
-- about time. Thirty-two of Platinum's 501 move animations build a 2D sprite out
-- of four resources -- NCGR pixels, NCLR palette, NCER cells, NANR animation --
-- and without this file the fourth is missing, so such a sprite can only ever be
-- drawn as one still frame.
--
-- !! NOTHING HERE WAS TAKEN FROM A REFERENCE. pret expects the NitroSystem SDK
-- headers for `NNSG2dAnimBankData` and does not ship them, so there is no
-- struct to read off. What follows was derived, and the derivation is the part
-- worth keeping.
--
-- WHAT IS IN A NANR. One KNBA section (ABNK, reversed like every Nitro tag),
-- whose fields begin 24 bytes into the file:
--
--   u16 sequenceCount
--   u16 frameCount            -- across the WHOLE file, not per sequence
--   u32 sequenceOffset        -- all three offsets are relative to byte 24
--   u32 frameOffset
--   u32 resultOffset
--   u32 reserved[2]
--
-- THE FRAME ARRAY WAS LOCATED BY A SIGNATURE, NOT BY TRUST. Every frame record
-- ends in the constant 0xBEEF, so the frame array can be found by scanning for
-- a run of `frameCount` records at stride 8 whose last halfword is 0xBEEF -- and
-- on all 37 members of wecellanm.narc that run begins at exactly
-- `24 + frameOffset`. That is what fixes the offsets' base at 24 rather than at
-- the section or the file start, and it fixes the frame stride at 8, without
-- either being assumed.
--
--   u32 resultOffset          -- into the result array, relative to ITS base
--   u16 duration              -- in frames
--   u16 0xBEEF
--
-- THE SEQUENCE STRIDE IS 16 AND WAS DERIVED THE SAME WAY: with the frame array
-- located independently, the sequence array runs from `24 + sequenceOffset` to
-- it, and that distance divided by `sequenceCount` is 16 on all 37 members. The
-- documented NNS sequence is twelve bytes of named fields; the four this port
-- cannot name sit between them and the frame offset, and are read past rather
-- than guessed at.
--
--   u16 frameCount            -- of THIS sequence
--   u16 loopStartFrame
--   u16 elementType           -- 0 = a bare cell index; 1 and 2 add transforms
--   u16 playbackMode
--   u32 unknown               -- 1 or 2 across the cartridge; not structural
--   u32 frameOffset           -- BYTES into the frame array
--
-- AND THEN IT CLOSES, TWICE OVER:
--   * every sequence's frame range TILES the file's frame array exactly -- 53
--     sequences over 186 frames on 37 members, no overlap and no gap. A wrong
--     stride or a wrong base does not tile 37 times by accident.
--   * every frame's result resolves to a cell index that EXISTS IN THE MATCHING
--     NCER -- a cross-archive test, wecellanm against wecell, 186 for 186. The
--     highest index any frame names is 9 and no bank is smaller than that.
--
-- A RESULT IS TWO BYTES AND ITS POSITION IS READ, NOT STEPPED. For elementType 0
-- the result is a u16 cell index, and the frames' own `resultOffset` values are
-- not evenly spaced: 0, 2, 4, 6, 8, then 12, because the cartridge pads between
-- one sequence's results and the next with 0xCCCC. Walking the array at a fixed
-- stride would read that padding as a cell index; following each frame's own
-- offset cannot.
--
-- WHAT THE CARTRIDGE ACTUALLY USES, measured over all 53 sequences: elementType
-- is 0 on every one, playbackMode is 1 on every one, and loopStartFrame is 0 on
-- every one. So the transforming element types and the reverse playback modes
-- are UNREACHED here rather than unimplemented, and this file says so instead of
-- carrying code no cartridge data would ever run.

local Gen4CellAnim = {}

local byte, floor = string.byte, math.floor

local function u16(s, at)
  local a, b = byte(s, at, at + 1)
  if not b then return nil end
  return a + b * 256
end

local function u32(s, at)
  local a, b, c, d = byte(s, at, at + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- THE FOUR ARCHIVES A 2D BATTLE SPRITE IS BUILT FROM, and they are four
-- SEPARATE NARCs rather than four members of one -- which is why this port's
-- existing cell-assembly helper does not fit: that one reads its tiles, palette
-- and bank out of a single archive.
--
-- The script names a member of each by index: `loadcharresobj`, `loadplttres`,
-- `loadcellresobj`, `loadanimresobj`. Measured over the 32 programs that use
-- them, `charRes == cellRes == animRes` on ALL 38 sprites -- the three always
-- come from the same index -- while the PALETTE sometimes differs, which is why
-- wepltt has 39 members where the others have 37.
Gen4CellAnim.ARCHIVE_CHAR = "/wazaeffect/effectclact/wechar.narc"
Gen4CellAnim.ARCHIVE_PALETTE = "/wazaeffect/effectclact/wepltt.narc"
Gen4CellAnim.ARCHIVE_CELL = "/wazaeffect/effectclact/wecell.narc"
Gen4CellAnim.ARCHIVE_ANIM = "/wazaeffect/effectclact/wecellanm.narc"

Gen4CellAnim.SECTION = "KNBA"
Gen4CellAnim.FRAME_PAD = 0xBEEF
Gen4CellAnim.FRAME_BYTES = 8
Gen4CellAnim.SEQUENCE_BYTES = 16
Gen4CellAnim.ELEMENT_INDEX = 0
Gen4CellAnim.ELEMENT_SRT = 1
Gen4CellAnim.ELEMENT_TRANSLATE = 2

-- parse(data, Gen4Graphics) -> { sequences = { { frames = { { cell, duration } },
--                                loopStart, elementType, playbackMode } } }
--   or nil, why
function Gen4CellAnim.parse(data, Gen4Graphics)
  local container = Gen4Graphics.container(data)
  if not container then return nil, "not an animation bank" end
  local section = container.sections[Gen4CellAnim.SECTION]
  if not section then return nil, "NANR has no KNBA section" end

  local d = container.data
  local fields = section.body
  local sequenceCount = u16(d, fields)
  local frameCount = u16(d, fields + 2)
  local sequenceOffset = u32(d, fields + 4)
  local frameOffset = u32(d, fields + 8)
  local resultOffset = u32(d, fields + 12)
  if not (sequenceCount and frameCount and sequenceOffset
          and frameOffset and resultOffset) then
    return nil, "NANR header is truncated"
  end

  local frameBase = fields + frameOffset
  local resultBase = fields + resultOffset
  local out = { sequences = {}, frameCount = frameCount }
  local seen = 0

  for s = 0, sequenceCount - 1 do
    local at = fields + sequenceOffset + s * Gen4CellAnim.SEQUENCE_BYTES
    local count = u16(d, at)
    local loopStart = u16(d, at + 2)
    local elementType = u16(d, at + 4)
    local playbackMode = u16(d, at + 6)
    local within = u32(d, at + 12)
    if not (count and within) then
      return nil, ("sequence %d is truncated"):format(s)
    end
    -- THE TILING IS A CHECK, NOT A COMMENT. A sequence starting mid-record or
    -- running past the file's own frame count means the stride or the base is
    -- wrong, and a reader that shrugged at it would return plausible rubbish.
    if within % Gen4CellAnim.FRAME_BYTES ~= 0 then
      return nil, ("sequence %d starts %d bytes into a frame"):format(s, within)
    end
    local first = within / Gen4CellAnim.FRAME_BYTES
    if first + count > frameCount then
      return nil, ("sequence %d runs to frame %d of %d")
        :format(s, first + count, frameCount)
    end

    local frames = {}
    for f = 0, count - 1 do
      local fa = frameBase + (first + f) * Gen4CellAnim.FRAME_BYTES
      local resultAt = u32(d, fa)
      local duration = u16(d, fa + 4)
      local pad = u16(d, fa + 6)
      if not (resultAt and duration and pad) then
        return nil, ("frame %d of sequence %d is truncated"):format(f, s)
      end
      if pad ~= Gen4CellAnim.FRAME_PAD then
        return nil, ("frame %d of sequence %d ends %04X, not BEEF")
          :format(f, s, pad)
      end
      -- ONLY elementType 0 OCCURS, and rather than pretend to handle the other
      -- two this refuses them: a transform read as an index would name a cell
      -- that happens to exist and draw the wrong picture silently.
      if elementType ~= Gen4CellAnim.ELEMENT_INDEX then
        return nil, ("sequence %d uses element type %d, which this port has "
                     .. "never seen in the cartridge"):format(s, elementType)
      end
      local cell = u16(d, resultBase + resultAt)
      if not cell then
        return nil, ("frame %d of sequence %d points past the results")
          :format(f, s)
      end
      frames[f + 1] = { cell = cell, duration = duration }
      seen = seen + 1
    end

    out.sequences[s + 1] = {
      frames = frames,
      loopStart = loopStart,
      elementType = elementType,
      playbackMode = playbackMode,
      unknown = u32(d, at + 8),
    }
  end

  -- EVERY FRAME IN THE FILE MUST BELONG TO A SEQUENCE. The header states a
  -- total; if the sequences between them account for fewer, something is not
  -- being read -- which is the failure a per-sequence walk cannot see.
  if seen ~= frameCount then
    return nil, ("the sequences account for %d frames, the header says %d")
      :format(seen, frameCount)
  end
  return out
end

-- frames(anim, sequence) -> the flat cell/duration list, or nil
function Gen4CellAnim.frames(anim, sequence)
  local seq = anim and anim.sequences and anim.sequences[(sequence or 0) + 1]
  return seq and seq.frames or nil
end

-- length(frames) -> how many frames the sequence runs for in total
function Gen4CellAnim.length(frames)
  local total = 0
  for _, f in ipairs(frames or {}) do total = total + (f.duration or 0) end
  return total
end

-- at(frames, tick) -> the cell index showing at `tick`, and the frame number.
--
-- Clamped rather than wrapped: `playbackMode` is 1 on every sequence in the
-- cartridge and a one-shot is what the move scripts wait on. A looping mode
-- would need its own arm here, and none occurs.
function Gen4CellAnim.at(frames, tick)
  tick = tonumber(tick) or 0
  local elapsed = 0
  for i, f in ipairs(frames or {}) do
    elapsed = elapsed + (f.duration or 0)
    if tick < elapsed then return f.cell, i end
  end
  local last = frames and frames[#frames]
  return last and last.cell or nil, frames and #frames or 0
end

-- WHICH PALETTE BANK A CELL BANK WANTS, and why it has to be asked at all.
--
-- On the hardware, OBJ palette memory is sixteen banks of sixteen colours shared
-- by every sprite on screen, and an NCER's OAM entries carry the bank number
-- they were authored against -- a number about the final VRAM layout, not about
-- the file. The script's `loadplttres ... paletteIndex` says where the resource
-- goes, and it is 1 on all 34 calls in the cartridge, so it distinguishes
-- nothing; the OAM field does.
--
-- MEASURED OVER ALL 37 CELL BANKS: not one of them mixes banks within itself,
-- thirty-six use bank 0, and member 0 uses bank 9. So a member has exactly one
-- answer, and the sensible reading is that the member's own palette file is
-- whatever ends up in that bank.
--
-- THE REDUCTION, NAMED: rather than emulate OBJ palette memory, the file's
-- colours are PADDED UP so the wanted bank lands on them. For thirty-six members
-- that is a no-op. For member 0 it is the difference between a 184x64 sprite and
-- a fully transparent rectangle, which is how the question came up.
function Gen4CellAnim.paletteFor(colours, bank)
  bank = tonumber(bank) or 0
  if type(colours) ~= "table" or bank <= 0 then return colours end
  local out = {}
  for _ = 1, bank * 16 do out[#out + 1] = { 0, 0, 0 } end
  for i = 1, #colours do out[#out + 1] = colours[i] end
  return out
end

-- bankOf(cellBank) -> the single OAM palette bank a cell bank uses, or nil when
-- it uses more than one (which no bank in the cartridge does).
function Gen4CellAnim.bankOf(cellBank)
  local found = nil
  for _, cell in ipairs((cellBank or {}).cells or {}) do
    for _, o in ipairs(cell.oam or {}) do
      if found == nil then found = o.palette
      elseif found ~= o.palette then return nil end
    end
  end
  return found or 0
end

-- check(data, Gen4Graphics) -> true, sequenceCount, frameCount   or false, why
function Gen4CellAnim.check(data, Gen4Graphics)
  local anim, why = Gen4CellAnim.parse(data, Gen4Graphics)
  if not anim then return false, why end
  local frames = 0
  for _, seq in ipairs(anim.sequences) do frames = frames + #seq.frames end
  return true, #anim.sequences, frames
end

return Gen4CellAnim
