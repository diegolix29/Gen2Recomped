-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 TEXTURE ANIMATION, evaluated at a frame.
--
-- `bm_anime.narc` animates the props standing on the map -- fountains, lakes,
-- waterfalls, doors, machines -- and NOT the terrain; 68 of its 95 animations
-- name a build model and none names anything in a land chunk.  See the import
-- side for that measurement.
--
-- TWO KINDS, and only one of them is played here:
--
--   BTA0  scrolls, scales and rotates a material's texture coordinates.  This
--         is what makes water move, and it is played.
--   BTP0  swaps which picture a material wears, frame by frame -- a door
--         opening, a screen flickering.  Played, now that where those pictures
--         live is settled rather than guessed: of the 16 build models carrying
--         a BTP0, ALL 16 have every one of that animation's texture names in
--         their OWN TEX0 -- no misses, and no model without a TEX0.  So the
--         alternate frames sit inside the model file beside the one they
--         replace, and the import stage writes them under the same
--         "<model>/<texture>" key as everything else.
--
-- THE UNITS ARE NORMALISED, measured rather than assumed.  Every scroll in the
-- archive runs its translate from 0.0 to exactly -1.0 over its own frame count
-- -- the waterfall to -2.0, two cycles in the same time -- with scale held at
-- 1.0.  A translate landing on whole units is one full wrap of the texture;
-- texel units would have run to 16 or 64.
--
--     funsui       16 frames   tT  0.0000 .. -1.0000
--     r04_w       121 frames   tS and tT  0.0000 .. -1.0000
--     wfall        61 frames   tT  0.0000 .. -2.0000
--     l_lake       61 frames   tS and tT  0.0000 .. -1.0000
--     machine_l04  60 frames   tS -0.0166 .. -1.0000

local Gen4TexAnim = {}

-- One channel's value at a frame.  A constant channel is stored as a list of
-- one, which is the cartridge's own encoding rather than a special case here.
local function at(list, frame, default)
  if type(list) ~= "table" or #list == 0 then return default end
  if #list == 1 then return list[1] end
  return list[frame % #list + 1]
end

-- The material states for one model at one frame, or nil when nothing animates
-- it.  The shape is what `Gen4Model:draw` takes as its third argument.
-- Which key of a pattern is showing at `frame`: the LAST key whose own frame
-- is at or before it.  Walked rather than indexed because the keys are sparse
-- -- `c1_s02` holds frame 0 for ten frames, then 1 for twenty, then 2 for
-- thirteen -- so key N is not frame N and treating it as though it were would
-- run every flipbook at the wrong speed.
local function keyAt(keys, frame)
  local found
  for _, key in ipairs(keys) do
    if (key.frame or 0) <= frame then found = key else break end
  end
  return found or keys[1]
end

-- `images` maps a texture NAME to the path the import stage wrote it under --
-- the model's own `patternImages`.  Without it the flipbooks are skipped
-- rather than drawn with whatever picture is nearest: a door showing the wrong
-- frame looks deliberate.
function Gen4TexAnim.materials(records, frame, images)
  if type(records) ~= "table" then return nil end
  local out, any = {}, false
  for _, record in ipairs(records) do
    if record.kind == "BTP0" and record.pattern and images then
      local period = tonumber(record.frames) or 1
      if period < 1 then period = 1 end
      for _, target in ipairs(record.pattern.targets or {}) do
        local keys = target.keys
        if target.name and type(keys) == "table" and keys[1] then
          local key = keyAt(keys, frame % period)
          local name = key and record.pattern.textures
            and record.pattern.textures[(key.texture or 0) + 1]
          local path = name and images[name]
          if path then
            local state = out[target.name] or {}
            state.image = path
            out[target.name] = state
            any = true
          end
        end
      end
    end
    if record.kind == "BTA0" and record.srt then
      for _, target in ipairs(record.srt) do
        if target.name then
          local sS = at(target.scaleS, frame, 1)
          local sT = at(target.scaleT, frame, 1)
          local sin = at(target.rotationSin, frame, 0)
          local cos = at(target.rotationCos, frame, 1)
          -- A rotation stored as a sine and a cosine pair that are BOTH zero
          -- is not a rotation of zero, it is a channel that was not written.
          -- Reading it as a matrix of zeros collapses the texture to a point.
          if sin == 0 and cos == 0 then sin, cos = 0, 1 end
          -- Merged rather than assigned: a material can carry BOTH a scroll
          -- and a flipbook, and writing a fresh table here would drop whichever
          -- of the two was evaluated first.
          local state = out[target.name] or {}
          state.uv = { sS * cos, sS * -sin, sT * sin, sT * cos,
                       at(target.translateS, frame, 0),
                       at(target.translateT, frame, 0) }
          out[target.name] = state
          any = true
        end
      end
    end
  end
  if not any then return nil end
  return out
end

-- Does anything here animate at all?  Asked once per model rather than per
-- frame.  A BTP0 counts only when the model actually carries the pictures its
-- keys name -- an older cache has the animation and not the frames, and
-- rebaking a chunk every frame to redraw an unchanging door is pure cost.
function Gen4TexAnim.animates(records, images)
  if type(records) ~= "table" then return false end
  for _, record in ipairs(records) do
    if record.kind == "BTA0" and record.srt then return true end
    if record.kind == "BTP0" and record.pattern and images then
      for _, name in ipairs(record.pattern.textures or {}) do
        if images[name] then return true end
      end
    end
  end
  return false
end

-- The longest animation in a set, which is the period the whole model repeats
-- on.  Used to keep the clock small rather than letting it run forever.
function Gen4TexAnim.period(records)
  local longest = 1
  for _, record in ipairs(records or {}) do
    local frames = tonumber(record.frames) or 0
    if frames > longest then longest = frames end
  end
  return longest
end

return Gen4TexAnim
