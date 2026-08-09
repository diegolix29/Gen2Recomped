-- Shiny colours for the 151 Stadium models, as the Stadium games define
-- them. GENERATED -- do not hand-edit. The colour model is documented in
-- the header of lib/ShinyPalette.lua.
--
-- Stadium does not ship a second set of textures for a shiny Pokemon. It
-- slides the colours it already has in HSL: a hue rotation in degrees,
-- plus saturation and lightness on a quantized -8..+8 scale where one
-- step is 12.5% (so +-8 is +-100%, exactly GIMP's Hue-Saturation range --
-- s = -8 is full greyscale, l = +8 is white).
--
-- FIVE SPECIES ARE DIFFERENT. Clefairy, Clefable, Jigglypuff, Wigglytuff
-- and Gyarados get a genuine alternate texture in Stadium, because no
-- single slide can produce their shiny: Jigglypuff's body must stay pink
-- while its irises rotate to green, and one rotation moves both or
-- neither. Those five carry `lut` -- an explicit before/after colour
-- mapping sampled from the verified texture pairs, listing only the
-- colours that actually change. A colour absent from the table is left
-- exactly as it was.
--
-- hueRange is the min/max hue a NON-shiny nicknamed mon can slide to in
-- Stadium (derived from the trainer ID and the nickname). Carried for
-- reference; nothing reads it today.

return {
  [1] = {
    name = "bulbasaur",
    hueRange = { min = -45, max = 70 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x52BD9C,
    slide = { h = -30, l = 2, s = -1 },
  },
  [2] = {
    name = "ivysaur",
    hueRange = { min = -40, max = 45 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x6AC5C5,
    slide = { h = -50, l = 2, s = 1 },
  },
  [3] = {
    name = "venusaur",
    hueRange = { min = -30, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x6ABDCD,
    slide = { h = -40, l = 2, s = 1 },
  },
  [4] = {
    name = "charmander",
    hueRange = { min = -25, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xEE8B31,
    slide = { h = 28, l = 0, s = -1 },
  },
  [5] = {
    name = "charmeleon",
    hueRange = { min = -10, max = 55 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xD54A6A,
    slide = { h = -20, l = 1, s = -1 },
  },
  [6] = {
    name = "charizard",
    hueRange = { min = -20, max = 15 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xF68B29,
    slide = { h = -136, l = 0, s = -6 },
  },
  [7] = {
    name = "squirtle",
    hueRange = { min = -50, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xACFFFF,
    slide = { h = 30, l = -3, s = 2 },
  },
  [8] = {
    name = "wartortle",
    hueRange = { min = -50, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x8BA4E6,
    slide = { h = -50, l = -3, s = -2 },
  },
  [9] = {
    name = "blastoise",
    hueRange = { min = -30, max = 35 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x7B9CBD,
    slide = { h = -35, l = -1, s = -3 },
  },
  [10] = {
    name = "caterpie",
    hueRange = { min = -30, max = 80 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x629441,
    slide = { h = -45, l = 2, s = -1 },
  },
  [11] = {
    name = "metapod",
    hueRange = { min = -20, max = 60 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xACF662,
    slide = { h = -55, l = 0, s = 0 },
  },
  [12] = {
    name = "butterfree",
    hueRange = { min = -40, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xD5F6F6,
    slide = { h = 140, l = 0, s = 0 },
  },
  [13] = {
    name = "weedle",
    hueRange = { min = 0, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xE67331,
    slide = { h = 46, l = 0, s = 0 },
  },
  [14] = {
    name = "kakuna",
    hueRange = { min = -25, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xDECD31,
    slide = { h = 30, l = 0, s = 0 },
  },
  [15] = {
    name = "beedrill",
    hueRange = { min = -20, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFB44A,
    slide = { h = 145, l = 0, s = -3 },
  },
  [16] = {
    name = "pidgey",
    hueRange = { min = -30, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFE6A4,
    slide = { h = 40, l = 1, s = -2 },
  },
  [17] = {
    name = "pidgeotto",
    hueRange = { min = -30, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFE6A4,
    slide = { h = 40, l = 1, s = 0 },
  },
  [18] = {
    name = "pidgeot",
    hueRange = { min = -35, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFE6A4,
    slide = { h = 40, l = 1, s = -3 },
  },
  [19] = {
    name = "rattata",
    hueRange = { min = -40, max = 60 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x9C6AC5,
    slide = { h = -105, l = 0, s = -5 },
  },
  [20] = {
    name = "raticate",
    hueRange = { min = -30, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xF6EEC5,
    slide = { h = -30, l = 1, s = -4 },
  },
  [21] = {
    name = "spearow",
    hueRange = { min = -30, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFE6A4,
    slide = { h = -25, l = 1, s = -2 },
  },
  [22] = {
    name = "fearow",
    hueRange = { min = -25, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xDCD294,
    slide = { h = 140, l = 3, s = -5 },
  },
  [23] = {
    name = "ekans",
    hueRange = { min = -30, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xAC7BBD,
    slide = { h = -155, l = -2, s = -5 },
  },
  [24] = {
    name = "arbok",
    hueRange = { min = -70, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xA48BBD,
    slide = { h = -80, l = 0, s = -4 },
  },
  [25] = {
    name = "pikachu",
    hueRange = { min = -15, max = 25 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFDE31,
    slide = { h = -25, l = 1, s = 0 },
  },
  [26] = {
    name = "raichu",
    hueRange = { min = -15, max = 25 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xF6A429,
    slide = { h = 25, l = 0, s = -2 },
  },
  [27] = {
    name = "sandshrew",
    hueRange = { min = -40, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xA49C52,
    slide = { h = -159, l = -1, s = -4 },
  },
  [28] = {
    name = "sandslash",
    hueRange = { min = -20, max = 25 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xCDBD08,
    slide = { h = 25, l = 1, s = -6 },
  },
  [29] = {
    name = "nidoran_f",
    hueRange = { min = -60, max = 70 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xD5DEF6,
    slide = { h = 70, l = -2, s = 2 },
  },
  [30] = {
    name = "nidorina",
    hueRange = { min = -80, max = 80 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x9CD5DE,
    slide = { h = 100, l = 0, s = 0 },
  },
  [31] = {
    name = "nidoqueen",
    hueRange = { min = -60, max = 80 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x7B9CBD,
    slide = { h = 50, l = 0, s = -5 },
  },
  [32] = {
    name = "nidoran_m",
    hueRange = { min = -70, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xF694D5,
    slide = { h = -96, l = 0, s = 0 },
  },
  [33] = {
    name = "nidorino",
    hueRange = { min = -70, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xE68BCD,
    slide = { h = -99, l = 0, s = 0 },
  },
  [34] = {
    name = "nidoking",
    hueRange = { min = -50, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xBD83C5,
    slide = { h = -60, l = 0, s = 0 },
  },
  [35] = {
    name = "clefairy",
    hueRange = { min = -40, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFC5C5,
    -- Stadium ships a real alternate texture for this one; 350
    -- colours move, every other colour stays exactly as it was.
    lut = {
      [0x080800]=0x010800, [0x100800]=0x020F00, [0x101000]=0x020F00, [0x181000]=0x031700,
      [0x181008]=0x081905, [0x201000]=0x041E00, [0x201800]=0x041E00, [0x201808]=0x082204,
      [0x291010]=0x29101D, [0x291800]=0x052700, [0x291808]=0x082C02, [0x291818]=0x291820,
      [0x292000]=0x052700, [0x310808]=0x31081D, [0x311010]=0x311021, [0x311818]=0x311825,
      [0x312000]=0x062F00, [0x312008]=0x083501, [0x312010]=0x0F340A, [0x312020]=0x312028,
      [0x312900]=0x062F00, [0x312908]=0x083501, [0x312910]=0x0F340A, [0x390000]=0x39001D,
      [0x390008]=0x39001D, [0x390808]=0x390821, [0x391818]=0x391829, [0x392020]=0x39202D,
      [0x392900]=0x073600, [0x392908]=0x083E00, [0x392910]=0x0F3D08, [0x392918]=0x173C11,
      [0x392929]=0x392931, [0x392939]=0x392931, [0x393108]=0x083E00, [0x410000]=0x410021,
      [0x410008]=0x410021, [0x410808]=0x410825, [0x410810]=0x410825, [0x412020]=0x412031,
      [0x412908]=0x094500, [0x412910]=0x0F4607, [0x412929]=0x412935, [0x413108]=0x094500,
      [0x413110]=0x0F4607, [0x413118]=0x174510, [0x4A0008]=0x4A0025, [0x4A0808]=0x4A0829,
      [0x4A0810]=0x4A0829, [0x4A2020]=0x4A2035, [0x4A3108]=0x0A4E00, [0x4A3110]=0x0F5006,
      [0x4A3118]=0x174F0E, [0x4A3131]=0x4A313E, [0x4A3910]=0x0F5006, [0x4A3918]=0x174F0E,
      [0x520810]=0x52082D, [0x521010]=0x521031, [0x521018]=0x521031, [0x521820]=0x521835,
      [0x522929]=0x52293E, [0x523131]=0x523142, [0x523910]=0x105904, [0x523931]=0x523142,
      [0x523939]=0x523946, [0x524110]=0x105904, [0x524118]=0x17580D, [0x5A1010]=0x5A1035,
      [0x5A2020]=0x5A203D, [0x5A3939]=0x5A394A, [0x5A4108]=0x0C5D00, [0x5A4110]=0x106203,
      [0x5A4118]=0x17600C, [0x5A4120]=0x1F5F15, [0x5A4129]=0x275E1F, [0x5A4139]=0x5A394A,
      [0x5A4141]=0x5A414E, [0x5A414A]=0x5A414E, [0x5A4A18]=0x17600C, [0x5A4A20]=0x1F5F15,
      [0x621010]=0x621039, [0x622929]=0x622946, [0x623131]=0x62314A, [0x623939]=0x62394E,
      [0x624110]=0x106B02, [0x624141]=0x624152, [0x624A10]=0x106B02, [0x624A18]=0x17690A,
      [0x624A20]=0x1F6813, [0x624A29]=0x27671D, [0x624A41]=0x624152, [0x625220]=0x1F6813,
      [0x6A1010]=0x6A103D, [0x6A2931]=0x6A294A, [0x6A3131]=0x6A314E, [0x6A3939]=0x6A3952,
      [0x6A4141]=0x6A4156, [0x6A4A31]=0x2F6E25, [0x6A4A4A]=0x6A4A5A, [0x6A5220]=0x1F7112,
      [0x6A5241]=0x6A4156, [0x734141]=0x73415A, [0x734A4A]=0x734A5E, [0x735231]=0x2F7824,
      [0x735241]=0x73415A, [0x73524A]=0x734A5E, [0x735252]=0x735263, [0x73525A]=0x735263,
      [0x735A4A]=0x734A5E, [0x7B2018]=0x7B184A, [0x7B4A4A]=0x7B4A63, [0x7B5252]=0x7B5266,
      [0x7B5A41]=0x7B415E, [0x7B5A4A]=0x7B4A63, [0x7B5A52]=0x7B5266, [0x7B5A5A]=0x7B5A6B,
      [0x7B625A]=0x7B5A6B, [0x832018]=0x83184E, [0x832020]=0x832052, [0x83414A]=0x834162,
      [0x834A52]=0x834A67, [0x835252]=0x83526A, [0x835A5A]=0x835A6E, [0x83624A]=0x834A67,
      [0x83625A]=0x835A6E, [0x8B3939]=0x8B3962, [0x8B4A4A]=0x8B4A6A, [0x8B5252]=0x8B526F,
      [0x8B5A5A]=0x8B5A72, [0x8B625A]=0x8B5A72, [0x8B6262]=0x8B6277, [0x8B6A52]=0x8B526F,
      [0x941818]=0x941856, [0x942018]=0x941856, [0x94525A]=0x945273, [0x945A5A]=0x945A77,
      [0x946262]=0x94627B, [0x946A62]=0x94627B, [0x946A6A]=0x946A7F, [0x946A73]=0x946A7F,
      [0x94735A]=0x945A77, [0x9C2020]=0x9C205E, [0x9C2920]=0x9C205E, [0x9C2929]=0x9C2963,
      [0x9C5A5A]=0x9C5A7B, [0x9C5A62]=0x9C5A7B, [0x9C6262]=0x9C627F, [0x9C626A]=0x9C627F,
      [0x9C6A6A]=0x9C6A83, [0x9C6A73]=0x9C6A83, [0x9C735A]=0x9C5A7B, [0x9C7362]=0x9C627F,
      [0x9C7373]=0x9C7388, [0x9C737B]=0x9C7388, [0xA42929]=0xA42967, [0xA43129]=0xA42967,
      [0xA43131]=0xA4316B, [0xA4626A]=0xA46283, [0xA46A6A]=0xA46A87, [0xA47373]=0xA4738C,
      [0xA47B62]=0xA46283, [0xA47B6A]=0xA46A87, [0xA47B73]=0xA4738C, [0xA47B7B]=0xA47B90,
      [0xA47B83]=0xA47B90, [0xA4836A]=0xA46A87, [0xA48383]=0xA48393, [0xAC3131]=0xAC316F,
      [0xAC3931]=0xAC316F, [0xAC3939]=0xAC3973, [0xAC4A41]=0xAC4177, [0xAC6A6A]=0xAC6A8B,
      [0xAC7373]=0xAC7390, [0xAC737B]=0xAC7390, [0xAC7B7B]=0xAC7B94, [0xAC8373]=0xAC7390,
      [0xAC837B]=0xAC7B94, [0xAC8383]=0xAC8398, [0xAC838B]=0xAC8398, [0xAC8B83]=0xAC8398,
      [0xAC8B8B]=0xAC8B9C, [0xAC948B]=0xAC8B9C, [0xB44139]=0xB43977, [0xB44141]=0xB4417B,
      [0xB44A41]=0xB4417B, [0xB44A4A]=0xB44A7F, [0xB45252]=0xB45283, [0xB47373]=0xB47394,
      [0xB47B7B]=0xB47B98, [0xB48383]=0xB4839C, [0xB48B7B]=0xB47B98, [0xB48B8B]=0xB48BA0,
      [0xB48B94]=0xB48BA0, [0xB49494]=0xB494A4, [0xBD4141]=0xBD417F, [0xBD4A41]=0xBD417F,
      [0xBD4A4A]=0xBD4A84, [0xBD524A]=0xBD4A84, [0xBD5252]=0xBD5288, [0xBD5A52]=0xBD5288,
      [0xBD5A5A]=0xBD5A8C, [0xBD7B7B]=0xBD7B9C, [0xBD8383]=0xBD83A0, [0xBD8B83]=0xBD83A0,
      [0xBD8B8B]=0xBD8BA4, [0xBD8B94]=0xBD8BA4, [0xBD947B]=0xBD7B9C, [0xBD9483]=0xBD83A0,
      [0xBD948B]=0xBD8BA4, [0xBD9494]=0xBD94A9, [0xBD949C]=0xBD94A9, [0xBDA49C]=0xBD9CAC,
      [0xBDA4A4]=0xBDA4B0, [0xBDA4AC]=0xBDA4B0, [0xBDACA4]=0xBDA4B0, [0xC5524A]=0xC54A88,
      [0xC55252]=0xC5528C, [0xC56262]=0xC56294, [0xC56A6A]=0xC56A98, [0xC58383]=0xC583A4,
      [0xC58B8B]=0xC58BA8, [0xC5948B]=0xC58BA8, [0xC59494]=0xC594AC, [0xC59C8B]=0xC58BA8,
      [0xC59C94]=0xC594AC, [0xC59C9C]=0xC59CB0, [0xC59CA4]=0xC59CB0, [0xC5ACAC]=0xC5ACB9,
      [0xCD5252]=0xCD5290, [0xCD5A52]=0xCD5290, [0xCD5A5A]=0xCD5A94, [0xCD625A]=0xCD5A94,
      [0xCD6262]=0xCD6298, [0xCD6A62]=0xCD6298, [0xCD736A]=0xCD6A9C, [0xCD7373]=0xCD73A0,
      [0xCD8B8B]=0xCD8BAC, [0xCD9494]=0xCD94B0, [0xCD9C94]=0xCD94B0, [0xCD9C9C]=0xCD9CB4,
      [0xCD9CA4]=0xCD9CB4, [0xCDA4A4]=0xCDA4B9, [0xCDACAC]=0xCDACBC, [0xCDB4B4]=0xCDB4C0,
      [0xD5625A]=0xD55A98, [0xD56262]=0xD5629C, [0xD56A62]=0xD5629C, [0xD57373]=0xD573A4,
      [0xD58B8B]=0xD58BB0, [0xD5948B]=0xD58BB0, [0xD59494]=0xD594B5, [0xD59C94]=0xD594B5,
      [0xD59C9C]=0xD59CB9, [0xD5A49C]=0xD59CB9, [0xD5A4A4]=0xD5A4BC, [0xD5A4AC]=0xD5A4BC,
      [0xD5ACAC]=0xD5ACC0, [0xD5B4B4]=0xD5B4C4, [0xD5BDBD]=0xD5BDC9, [0xD5C5C5]=0xD5C5CD,
      [0xDE6A62]=0xDE62A0, [0xDE6A6A]=0xDE6AA4, [0xDE736A]=0xDE6AA4, [0xDE7373]=0xDE73A9,
      [0xDE7B73]=0xDE73A9, [0xDE7B7B]=0xDE7BAD, [0xDE9494]=0xDE94B9, [0xDE9C94]=0xDE94B9,
      [0xDE9C9C]=0xDE9CBD, [0xDEA4A4]=0xDEA4C1, [0xDEA4AC]=0xDEA4C1, [0xDEACA4]=0xDEA4C1,
      [0xDEACAC]=0xDEACC5, [0xDEACB4]=0xDEACC5, [0xDEB4B4]=0xDEB4C9, [0xDEBDBD]=0xDEBDCE,
      [0xDEC5C5]=0xDEC5D2, [0xE6736A]=0xE66AA8, [0xE67373]=0xE673AD, [0xE67B73]=0xE673AD,
      [0xE67B7B]=0xE67BB1, [0xE67B8B]=0xE67BB1, [0xE67B94]=0xE67BB1, [0xE6837B]=0xE67BB1,
      [0xE68383]=0xE683B4, [0xE68394]=0xE683B4, [0xE68B83]=0xE683B4, [0xE69494]=0xE694BD,
      [0xE69CA4]=0xE69CC1, [0xE6A4A4]=0xE6A4C5, [0xE6A4AC]=0xE6A4C5, [0xE6ACA4]=0xE6A4C5,
      [0xE6ACAC]=0xE6ACC9, [0xE6ACB4]=0xE6ACC9, [0xE6B4B4]=0xE6B4CD, [0xE6B4BD]=0xE6B4CD,
      [0xE6BDBD]=0xE6BDD2, [0xE6C5C5]=0xE6C5D6, [0xE6CDCD]=0xE6CDDA, [0xE6CDD5]=0xE6CDDA,
      [0xEE7B7B]=0xEE7BB5, [0xEE837B]=0xEE7BB5, [0xEE8383]=0xEE83B9, [0xEE8394]=0xEE83B9,
      [0xEE8B83]=0xEE83B9, [0xEE8B8B]=0xEE8BBD, [0xEE8B9C]=0xEE8BBD, [0xEE948B]=0xEE8BBD,
      [0xEE9494]=0xEE94C1, [0xEE949C]=0xEE94C1, [0xEE94A4]=0xEE94C1, [0xEE9CA4]=0xEE9CC5,
      [0xEEA4AC]=0xEEA4C9, [0xEEACAC]=0xEEACCD, [0xEEACB4]=0xEEACCD, [0xEEB4AC]=0xEEACCD,
      [0xEEB4B4]=0xEEB4D1, [0xEEB4BD]=0xEEB4D1, [0xEEBDB4]=0xEEB4D1, [0xEEBDBD]=0xEEBDD6,
      [0xEEC5BD]=0xEEBDD6, [0xEEC5C5]=0xEEC5DA, [0xEECDCD]=0xEECDDE, [0xEED5D5]=0xEED5E2,
      [0xF69CA4]=0xF69CC9, [0xF69CAC]=0xF69CC9, [0xF6A4AC]=0xF6A4CD, [0xF6ACAC]=0xF6ACD1,
      [0xF6ACB4]=0xF6ACD1, [0xF6B4B4]=0xF6B4D5, [0xF6B4BD]=0xF6B4D5, [0xF6BDB4]=0xF6B4D5,
      [0xF6BDBD]=0xF6BDDA, [0xF6BDC5]=0xF6BDDA, [0xF6C5C5]=0xF6C5DE, [0xF6CDCD]=0xF6CDE2,
      [0xF6D5D5]=0xF6D5E6, [0xFFB4B4]=0xFFB4DA, [0xFFB4BD]=0xFFB4DA, [0xFFBDBD]=0xFFBDDE,
      [0xFFBDC5]=0xFFBDDE, [0xFFC5BD]=0xFFBDDE, [0xFFC5C5]=0xFFC5E2, [0xFFC5CD]=0xFFC5E2,
      [0xFFCDC5]=0xFFC5E2, [0xFFCDCD]=0xFFCDE6, [0xFFD5CD]=0xFFCDE6, [0xFFD5D5]=0xFFD5EA,
      [0xFFDEDE]=0xFFDEEE, [0xFFE6E6]=0xFFE6F2,
    },
  },
  [36] = {
    name = "clefable",
    hueRange = { min = -40, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFD5CD,
    -- Stadium ships a real alternate texture for this one; 223
    -- colours move, every other colour stays exactly as it was.
    lut = {
      [0x080000]=0x080004, [0x080800]=0x010800, [0x100808]=0x10080C, [0x180000]=0x18000C,
      [0x180808]=0x180810, [0x181010]=0x181014, [0x200000]=0x200010, [0x200808]=0x200814,
      [0x201010]=0x201018, [0x290000]=0x290015, [0x290808]=0x290819, [0x291010]=0x29101D,
      [0x292018]=0x291820, [0x310000]=0x310019, [0x310808]=0x31081D, [0x311010]=0x311021,
      [0x312020]=0x312028, [0x312029]=0x312028, [0x390008]=0x39001D, [0x391010]=0x391025,
      [0x391818]=0x391829, [0x392929]=0x392931, [0x393129]=0x392931, [0x410000]=0x410021,
      [0x410808]=0x410825, [0x413129]=0x412935, [0x4A0000]=0x4A0025, [0x4A3131]=0x4A313E,
      [0x520000]=0x520029, [0x521000]=0x520029, [0x523939]=0x523946, [0x524139]=0x523946,
      [0x5A0000]=0x5A002D, [0x5A1808]=0x5A0831, [0x5A4141]=0x5A414E, [0x5A4A41]=0x5A414E,
      [0x620000]=0x620031, [0x622010]=0x621039, [0x622020]=0x622041, [0x622918]=0x62183D,
      [0x6A0000]=0x6A0035, [0x6A2918]=0x6A1841, [0x6A2920]=0x6A2045, [0x6A3120]=0x6A2045,
      [0x730000]=0x73003A, [0x733929]=0x73294E, [0x735252]=0x735263, [0x735A52]=0x735263,
      [0x7B4131]=0x7B3156, [0x7B5252]=0x7B5266, [0x7B625A]=0x7B5A6B, [0x834141]=0x834162,
      [0x834A39]=0x83395E, [0x834A41]=0x834162, [0x835241]=0x834162, [0x83625A]=0x835A6E,
      [0x8B4A4A]=0x8B4A6A, [0x94524A]=0x944A6F, [0x945A5A]=0x945A77, [0x946A6A]=0x946A7F,
      [0x94736A]=0x946A7F, [0x9C5252]=0x9C5277, [0x9C6A62]=0x9C627F, [0x9C7362]=0x9C627F,
      [0x9C7B73]=0x9C7388, [0xA4524A]=0xA44A77, [0xA46262]=0xA46283, [0xA47362]=0xA46283,
      [0xA4736A]=0xA46A87, [0xA47B6A]=0xA46A87, [0xA4837B]=0xA47B90, [0xA48383]=0xA48393,
      [0xA48B83]=0xA48393, [0xAC736A]=0xAC6A8B, [0xAC8373]=0xAC7390, [0xAC8B83]=0xAC8398,
      [0xAC8B8B]=0xAC8B9C, [0xAC948B]=0xAC8B9C, [0xB4948B]=0xB48BA0, [0xB49494]=0xB494A4,
      [0xB49C94]=0xB494A4, [0xBD6262]=0xBD6290, [0xBD7373]=0xBD7398, [0xBD9C94]=0xBD94A9,
      [0xBD9C9C]=0xBD9CAC, [0xBDA494]=0xBD94A9, [0xBDA49C]=0xBD9CAC, [0xBDA4A4]=0xBDA4B0,
      [0xC5625A]=0xC55A90, [0xC5736A]=0xC56A98, [0xC57B73]=0xC5739C, [0xC59C8B]=0xC58BA8,
      [0xC59C94]=0xC594AC, [0xC5A494]=0xC594AC, [0xC5A49C]=0xC59CB0, [0xC5AC9C]=0xC59CB0,
      [0xC5ACA4]=0xC5A4B4, [0xCD949C]=0xCD94B0, [0xCD9C9C]=0xCD9CB4, [0xCDA49C]=0xCD9CB4,
      [0xCDA4A4]=0xCDA4B9, [0xCDAC9C]=0xCD9CB4, [0xCDACA4]=0xCDA4B9, [0xCDB4A4]=0xCDA4B9,
      [0xCDB4AC]=0xCDACBC, [0xCDB4B4]=0xCDB4C0, [0xCDBDB4]=0xCDB4C0, [0xD56A6A]=0xD56AA0,
      [0xD594A4]=0xD594B5, [0xD59C9C]=0xD59CB9, [0xD59CA4]=0xD59CB9, [0xD59CAC]=0xD59CB9,
      [0xD5A4A4]=0xD5A4BC, [0xD5A4AC]=0xD5A4BC, [0xD5ACA4]=0xD5A4BC, [0xD5ACAC]=0xD5ACC0,
      [0xD5ACB4]=0xD5ACC0, [0xD5B4A4]=0xD5A4BC, [0xD5B4AC]=0xD5ACC0, [0xD5B4B4]=0xD5B4C4,
      [0xD5BDAC]=0xD5ACC0, [0xD5BDB4]=0xD5B4C4, [0xD5C5BD]=0xD5BDC9, [0xDE7B73]=0xDE73A9,
      [0xDE94A4]=0xDE94B9, [0xDE9CA4]=0xDE9CBD, [0xDE9CAC]=0xDE9CBD, [0xDEA4AC]=0xDEA4C1,
      [0xDEA4B4]=0xDEA4C1, [0xDEACB4]=0xDEACC5, [0xDEACBD]=0xDEACC5, [0xDEB4AC]=0xDEACC5,
      [0xDEB4B4]=0xDEB4C9, [0xDEBDAC]=0xDEACC5, [0xDEBDB4]=0xDEB4C9, [0xDEBDBD]=0xDEBDCE,
      [0xDEC5B4]=0xDEB4C9, [0xDEC5BD]=0xDEBDCE, [0xDECDBD]=0xDEBDCE, [0xDECDC5]=0xDEC5D2,
      [0xE67373]=0xE673AD, [0xE67B73]=0xE673AD, [0xE68B9C]=0xE68BB9, [0xE6949C]=0xE694BD,
      [0xE694A4]=0xE694BD, [0xE694AC]=0xE694BD, [0xE69CA4]=0xE69CC1, [0xE69CAC]=0xE69CC1,
      [0xE69CB4]=0xE69CC1, [0xE6A4AC]=0xE6A4C5, [0xE6A4B4]=0xE6A4C5, [0xE6ACA4]=0xE6A4C5,
      [0xE6ACB4]=0xE6ACC9, [0xE6B4AC]=0xE6ACC9, [0xE6BDB4]=0xE6B4CD, [0xE6BDBD]=0xE6BDD2,
      [0xE6C5B4]=0xE6B4CD, [0xE6C5BD]=0xE6BDD2, [0xE6C5C5]=0xE6C5D6, [0xE6CDBD]=0xE6BDD2,
      [0xE6CDC5]=0xE6C5D6, [0xE6D5CD]=0xE6CDDA, [0xEE7373]=0xEE73B1, [0xEE7B73]=0xEE73B1,
      [0xEE8B9C]=0xEE8BBD, [0xEE949C]=0xEE94C1, [0xEE94A4]=0xEE94C1, [0xEE9CA4]=0xEE9CC5,
      [0xEE9CAC]=0xEE9CC5, [0xEE9CB4]=0xEE9CC5, [0xEEA4AC]=0xEEA4C9, [0xEEA4B4]=0xEEA4C9,
      [0xEEA4BD]=0xEEA4C9, [0xEEACB4]=0xEEACCD, [0xEEACBD]=0xEEACCD, [0xEEB4BD]=0xEEB4D1,
      [0xEEBDB4]=0xEEB4D1, [0xEEC5B4]=0xEEB4D1, [0xEEC5BD]=0xEEBDD6, [0xEEC5C5]=0xEEC5DA,
      [0xEECDBD]=0xEEBDD6, [0xEECDC5]=0xEEC5DA, [0xEECDCD]=0xEECDDE, [0xEED5C5]=0xEEC5DA,
      [0xEED5CD]=0xEECDDE, [0xEEDED5]=0xEED5E2, [0xF68B9C]=0xF68BC1, [0xF6949C]=0xF694C5,
      [0xF694A4]=0xF694C5, [0xF69CA4]=0xF69CC9, [0xF69CAC]=0xF69CC9, [0xF6A4AC]=0xF6A4CD,
      [0xF6A4B4]=0xF6A4CD, [0xF6AC9C]=0xF69CC9, [0xF6BDAC]=0xF6ACD1, [0xF6C5B4]=0xF6B4D5,
      [0xF6C5BD]=0xF6BDDA, [0xF6CDBD]=0xF6BDDA, [0xF6CDC5]=0xF6C5DE, [0xF6D5C5]=0xF6C5DE,
      [0xF6D5CD]=0xF6CDE2, [0xF6D5D5]=0xF6D5E6, [0xF6DECD]=0xF6CDE2, [0xF6DED5]=0xF6D5E6,
      [0xF6E6DE]=0xF6DEEA, [0xFF8B9C]=0xFF8BC5, [0xFF949C]=0xFF94CA, [0xFF94A4]=0xFF94CA,
      [0xFF9CA4]=0xFF9CCE, [0xFFC5B4]=0xFFB4DA, [0xFFCDBD]=0xFFBDDE, [0xFFCDC5]=0xFFC5E2,
      [0xFFD5C5]=0xFFC5E2, [0xFFD5CD]=0xFFCDE6, [0xFFDECD]=0xFFCDE6, [0xFFDED5]=0xFFD5EA,
      [0xFFE6D5]=0xFFD5EA, [0xFFE6DE]=0xFFDEEE, [0xFFEEDE]=0xFFDEEE, [0xFFEEE6]=0xFFE6F2,
      [0xFFEEEE]=0xFFEEF6, [0xFFF6EE]=0xFFEEF6, [0xFFF6F6]=0xFFF6FB,
    },
  },
  [37] = {
    name = "vulpix",
    hueRange = { min = -30, max = 35 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xCD9C8B,
    slide = { h = 27, l = 0, s = 3 },
  },
  [38] = {
    name = "ninetales",
    hueRange = { min = -30, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFEEB4,
    slide = { h = -130, l = 0, s = -2 },
  },
  [39] = {
    name = "jigglypuff",
    hueRange = { min = -40, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFCDDE,
    -- Stadium ships a real alternate texture for this one; 394
    -- colours move, every other colour stays exactly as it was.
    lut = {
      [0x002018]=0x122000, [0x082018]=0x152206, [0x082920]=0x1A2B06, [0x083931]=0x233D04,
      [0x103931]=0x273C0D, [0x104139]=0x2B450C, [0x104A39]=0x304E0C, [0x183939]=0x2A3B16,
      [0x184139]=0x2F4415, [0x184A39]=0x344E14, [0x184A41]=0x344E14, [0x18524A]=0x385614,
      [0x185A4A]=0x3D5F13, [0x204141]=0x32431E, [0x204A41]=0x374D1D, [0x204A4A]=0x374D1D,
      [0x20524A]=0x3C561C, [0x205A52]=0x405E1C, [0x206252]=0x45671B, [0x20625A]=0x45671B,
      [0x206A5A]=0x49701A, [0x206A62]=0x49701A, [0x294141]=0x364327, [0x294A41]=0x3B4C27,
      [0x294A4A]=0x3B4C27, [0x29524A]=0x405526, [0x295252]=0x405526, [0x295A52]=0x445E25,
      [0x295A5A]=0x445E25, [0x296252]=0x496625, [0x29625A]=0x496625, [0x296A5A]=0x4D6F24,
      [0x296A62]=0x4D6F24, [0x297362]=0x527923, [0x29736A]=0x527923, [0x31524A]=0x43542F,
      [0x315252]=0x43542F, [0x315A52]=0x485D2E, [0x315A5A]=0x485D2E, [0x31625A]=0x4C662D,
      [0x316A62]=0x516E2D, [0x317362]=0x56782C, [0x31736A]=0x56782C, [0x317B6A]=0x5A812B,
      [0x317B73]=0x5A812B, [0x395252]=0x475437, [0x395A52]=0x4B5C37, [0x395A5A]=0x4B5C37,
      [0x395A62]=0x506536, [0x39625A]=0x506536, [0x396262]=0x506536, [0x396A62]=0x546E35,
      [0x39736A]=0x597735, [0x397B6A]=0x5E8034, [0x397B73]=0x5E8034, [0x398373]=0x628933,
      [0x398B7B]=0x679133, [0x415A5A]=0x4F5C3F, [0x416262]=0x53643F, [0x416A6A]=0x586D3E,
      [0x41736A]=0x5D773D, [0x417373]=0x5D773D, [0x417B6A]=0x617F3D, [0x417B73]=0x617F3D,
      [0x418373]=0x66883C, [0x41837B]=0x66883C, [0x418B7B]=0x6A913B, [0x418B83]=0x6A913B,
      [0x419483]=0x6F9A3B, [0x41948B]=0x6F9A3B, [0x41A494]=0x78AB3A, [0x4A3139]=0x483348,
      [0x4A6A6A]=0x5C6C48, [0x4A6A73]=0x617647, [0x4A7373]=0x617647, [0x4A7B73]=0x657F46,
      [0x4A837B]=0x6A8746, [0x4A8B83]=0x6E9045, [0x4A9483]=0x739A44, [0x4A948B]=0x739A44,
      [0x4A9C8B]=0x78A244, [0x4AA494]=0x7CAB43, [0x4AAC9C]=0x81B343, [0x523139]=0x503350,
      [0x523141]=0x503350, [0x523941]=0x503B50, [0x527373]=0x647550, [0x52737B]=0x697E4F,
      [0x527B7B]=0x697E4F, [0x528383]=0x6D874E, [0x52948B]=0x77994D, [0x529C8B]=0x7BA24C,
      [0x529C94]=0x7BA24C, [0x52A494]=0x80AA4C, [0x52A49C]=0x80AA4C, [0x52AC9C]=0x84B34B,
      [0x5A3941]=0x583B58, [0x5A394A]=0x583B58, [0x5A414A]=0x584358, [0x5A4152]=0x584358,
      [0x5A737B]=0x6C7D58, [0x5A7B7B]=0x6C7D58, [0x5A7B83]=0x718657, [0x5A837B]=0x718657,
      [0x5A8383]=0x718657, [0x5A948B]=0x7A9856, [0x5A9C94]=0x7FA155, [0x5AA494]=0x83AA54,
      [0x5AA49C]=0x83AA54, [0x5AAC9C]=0x88B254, [0x5AACA4]=0x88B254, [0x5AB4A4]=0x8CBB53,
      [0x62394A]=0x5F3C5F, [0x62414A]=0x604360, [0x62A49C]=0x87A95D, [0x62AC9C]=0x8BB25C,
      [0x62B4A4]=0x90BA5C, [0x62B4AC]=0x90BA5C, [0x6A414A]=0x674467, [0x6A948B]=0x819767,
      [0x6AB4A4]=0x93BA64, [0x6AB4AC]=0x93BA64, [0x6ABDAC]=0x98C364, [0x6ABDB4]=0x98C364,
      [0x6AC5B4]=0x9DCC63, [0x6AC5BD]=0x9DCC63, [0x73525A]=0x715471, [0x73C5B4]=0xA1CB6D,
      [0x73C5BD]=0xA1CB6D, [0x7B4A5A]=0x774E77, [0x7B525A]=0x785578, [0x7B5A62]=0x795C79,
      [0x7B9CA4]=0x92A778, [0x7BB4AC]=0x9BB877, [0x7BBDB4]=0xA0C276, [0x7BC5B4]=0xA4CB75,
      [0x7BC5BD]=0xA4CB75, [0x7BCDBD]=0xA9D375, [0x7BCDC5]=0xA9D375, [0x7BD5C5]=0xADDC74,
      [0x83525A]=0x7F567F, [0x835262]=0x7F567F, [0x835A62]=0x805D80, [0x835A6A]=0x805D80,
      [0x839CA4]=0x95A681, [0x83A4A4]=0x95A681, [0x83ACA4]=0x9AAF80, [0x83C5BD]=0xA8CA7E,
      [0x83CDC5]=0xACD37D, [0x83D5C5]=0xB1DB7D, [0x83D5CD]=0xB1DB7D, [0x83DECD]=0xB6E57C,
      [0x8B5262]=0x875687, [0x8B5A62]=0x875E87, [0x8B5A6A]=0x875E87, [0x8B626A]=0x886588,
      [0x8BA4AC]=0x9DAE89, [0x8BB4AC]=0xA2B788, [0x8BB4B4]=0xA2B788, [0x8BBDB4]=0xA7C187,
      [0x8BCDC5]=0xB0D286, [0x8BD5CD]=0xB4DB85, [0x945A6A]=0x905E90, [0x94626A]=0x906690,
      [0x946273]=0x906690, [0x946A73]=0x916D91, [0x946A7B]=0x916D91, [0x94ACB4]=0xA6B692,
      [0x94B4AC]=0xA6B692, [0x94B4B4]=0xA6B692, [0x94BDB4]=0xABC091, [0x94D5CD]=0xB8DA8F,
      [0x94DED5]=0xBDE48E, [0x94EEE6]=0xC6F58D, [0x9C6273]=0x986698, [0x9C6A73]=0x986E98,
      [0x9C6A7B]=0x986E98, [0x9C737B]=0x997699, [0x9C7383]=0x997699, [0x9CB4BD]=0xAEBF9A,
      [0x9CBDBD]=0xAEBF9A, [0x9CC5BD]=0xB3C899, [0x9CC5C5]=0xB3C899, [0x9CDED5]=0xC1E397,
      [0x9CE6DE]=0xC5EC96, [0xA44141]=0x9D489D, [0xA46A7B]=0xA06EA0, [0xA4737B]=0xA077A0,
      [0xA47383]=0xA077A0, [0xA47B83]=0xA17EA1, [0xA47B8B]=0xA17EA1, [0xA4838B]=0xA285A2,
      [0xA4BDBD]=0xB2BFA2, [0xA4CDC5]=0xBBD0A1, [0xA4E6DE]=0xC9EB9F, [0xA4EEDE]=0xCDF49E,
      [0xAC4A4A]=0xA551A5, [0xAC4A52]=0xA551A5, [0xAC525A]=0xA559A5, [0xAC7383]=0xA877A8,
      [0xAC838B]=0xA986A9, [0xAC8394]=0xA986A9, [0xAC8B94]=0xAA8DAA, [0xACBDC5]=0xBAC7AA,
      [0xACC5C5]=0xBAC7AA, [0xACCDCD]=0xBECFAA, [0xACEEE6]=0xD1F3A7, [0xB44A52]=0xAC52AC,
      [0xB45252]=0xAD59AD, [0xB45A5A]=0xAD61AD, [0xB45A62]=0xAD61AD, [0xB47B8B]=0xB07FB0,
      [0xB4838B]=0xB087B0, [0xB48394]=0xB087B0, [0xB48B94]=0xB18EB1, [0xB48B9C]=0xB18EB1,
      [0xB4949C]=0xB296B2, [0xB4C5CD]=0xC2CFB2, [0xB4EEE6]=0xD4F2B0, [0xB4F6EE]=0xD9FBAF,
      [0xBD525A]=0xB55AB5, [0xBD5A62]=0xB661B6, [0xBD6262]=0xB669B6, [0xBD626A]=0xB669B6,
      [0xBD6A6A]=0xB770B7, [0xBD838B]=0xB987B9, [0xBD8394]=0xB987B9, [0xBD8B94]=0xB98FB9,
      [0xBD8B9C]=0xB98FB9, [0xBD949C]=0xBA97BA, [0xBD94A4]=0xBA97BA, [0xBDD5D5]=0xCAD7BB,
      [0xBDEEE6]=0xD8F2B9, [0xBDEEEE]=0xD8F2B9, [0xBDF6EE]=0xDDFAB9, [0xC55A62]=0xBD62BD,
      [0xC5626A]=0xBE69BE, [0xC56A6A]=0xBE71BE, [0xC56A73]=0xBE71BE, [0xC57373]=0xBF79BF,
      [0xC5737B]=0xBF79BF, [0xC58B9C]=0xC18FC1, [0xC5949C]=0xC198C1, [0xC594A4]=0xC198C1,
      [0xC59CA4]=0xC29FC2, [0xC5CDD5]=0xCED6C4, [0xC5D5D5]=0xCED6C4, [0xC5D5DE]=0xD3E0C3,
      [0xC5DEDE]=0xD3E0C3, [0xC5EEEE]=0xDCF1C2, [0xC5F6EE]=0xE0FAC1, [0xC5F6F6]=0xE0FAC1,
      [0xC5FFF6]=0xE5FFC5, [0xCD6A73]=0xC671C6, [0xCD7373]=0xC67AC6, [0xCD737B]=0xC67AC6,
      [0xCD7B7B]=0xC781C7, [0xCD7B83]=0xC781C7, [0xCD8383]=0xC789C7, [0xCD838B]=0xC789C7,
      [0xCD949C]=0xC998C9, [0xCD94A4]=0xC998C9, [0xCD9CA4]=0xC9A0C9, [0xCD9CAC]=0xC9A0C9,
      [0xCDA4AC]=0xCAA7CA, [0xCDD5DE]=0xD6DFCC, [0xCDDEDE]=0xD6DFCC, [0xCDF6EE]=0xE4F9CA,
      [0xCDF6F6]=0xE4F9CA, [0xCDFFF6]=0xE8FFCD, [0xD5737B]=0xCE7ACE, [0xD57B83]=0xCE82CE,
      [0xD58383]=0xCF89CF, [0xD5838B]=0xCF89CF, [0xD58B8B]=0xCF91CF, [0xD58B94]=0xCF91CF,
      [0xD58B9C]=0xCF91CF, [0xD59494]=0xD099D0, [0xD5949C]=0xD099D0, [0xD59CA4]=0xD1A0D1,
      [0xD59CAC]=0xD1A0D1, [0xD5A4AC]=0xD1A8D1, [0xD5A4B4]=0xD1A8D1, [0xD5ACB4]=0xD2AFD2,
      [0xD5DEE6]=0xDEE7D4, [0xD5E6E6]=0xDEE7D4, [0xD5FFF6]=0xECFFD5, [0xD5FFFF]=0xECFFD5,
      [0xDE737B]=0xD67BD6, [0xDE8383]=0xD78AD7, [0xDE838B]=0xD78AD7, [0xDE8394]=0xD78AD7,
      [0xDE8B8B]=0xD891D8, [0xDE8B94]=0xD891D8, [0xDE8B9C]=0xD891D8, [0xDE9494]=0xD89AD8,
      [0xDE949C]=0xD89AD8, [0xDE94A4]=0xD89AD8, [0xDE9C9C]=0xD9A1D9, [0xDE9CA4]=0xD9A1D9,
      [0xDEA4AC]=0xDAA8DA, [0xDEA4B4]=0xDAA8DA, [0xDEACB4]=0xDAB0DA, [0xDEACBD]=0xDAB0DA,
      [0xDEB4BD]=0xDBB7DB, [0xDEF6F6]=0xEBF8DC, [0xDEFFF6]=0xF0FFDE, [0xDEFFFF]=0xF0FFDE,
      [0xE67B7B]=0xDE83DE, [0xE6838B]=0xDF8ADF, [0xE68B94]=0xDF92DF, [0xE68B9C]=0xDF92DF,
      [0xE69494]=0xE09AE0, [0xE6949C]=0xE09AE0, [0xE69C9C]=0xE0A2E0, [0xE69CA4]=0xE0A2E0,
      [0xE69CAC]=0xE0A2E0, [0xE6A4A4]=0xE1A9E1, [0xE6A4AC]=0xE1A9E1, [0xE6A4B4]=0xE1A9E1,
      [0xE6ACAC]=0xE2B0E2, [0xE6ACB4]=0xE2B0E2, [0xE6ACBD]=0xE2B0E2, [0xE6B4B4]=0xE2B8E2,
      [0xE6B4BD]=0xE2B8E2, [0xE6B4C5]=0xE2B8E2, [0xE6BDC5]=0xE3C0E3, [0xE6BDCD]=0xE3C0E3,
      [0xE6E6EE]=0xEAEFE5, [0xE6EEEE]=0xEAEFE5, [0xE6F6F6]=0xEFF7E5, [0xE6FFFF]=0xF4FFE6,
      [0xEE8B8B]=0xE792E7, [0xEE9494]=0xE79BE7, [0xEE949C]=0xE79BE7, [0xEE9C9C]=0xE8A2E8,
      [0xEE9CA4]=0xE8A2E8, [0xEEA4A4]=0xE8AAE8, [0xEEA4AC]=0xE8AAE8, [0xEEA4B4]=0xE8AAE8,
      [0xEEACAC]=0xE9B1E9, [0xEEACB4]=0xE9B1E9, [0xEEACBD]=0xE9B1E9, [0xEEB4BD]=0xEAB8EA,
      [0xEEB4C5]=0xEAB8EA, [0xEEBDC5]=0xEAC1EA, [0xEEBDCD]=0xEAC1EA, [0xEEC5D5]=0xEBC8EB,
      [0xEEEEF6]=0xF2F7ED, [0xEEF6F6]=0xF2F7ED, [0xEEFFFF]=0xF7FFEE, [0xF68383]=0xED8CED,
      [0xF68B94]=0xEE93EE, [0xF69494]=0xEF9BEF, [0xF69C9C]=0xEFA3EF, [0xF69CA4]=0xEFA3EF,
      [0xF6A4A4]=0xF0AAF0, [0xF6A4AC]=0xF0AAF0, [0xF6ACAC]=0xF0B2F0, [0xF6B4B4]=0xF1B9F1,
      [0xF6B4BD]=0xF1B9F1, [0xF6B4C5]=0xF1B9F1, [0xF6BDC5]=0xF2C1F2, [0xF6BDCD]=0xF2C1F2,
      [0xF6C5CD]=0xF2C9F2, [0xF6C5D5]=0xF2C9F2, [0xF6D5DE]=0xF4D7F4, [0xF6FFFF]=0xFBFFF6,
      [0xFF8383]=0xF68CF6, [0xFF8B8B]=0xF694F6, [0xFF9494]=0xF79CF7, [0xFF949C]=0xF79CF7,
      [0xFF9C9C]=0xF8A3F8, [0xFF9CA4]=0xF8A3F8, [0xFFA4A4]=0xF8ABF8, [0xFFA4AC]=0xF8ABF8,
      [0xFFACAC]=0xF9B2F9, [0xFFACB4]=0xF9B2F9, [0xFFB4B4]=0xF9BAF9, [0xFFB4BD]=0xF9BAF9,
      [0xFFBDBD]=0xFAC2FA, [0xFFBDC5]=0xFAC2FA, [0xFFBDCD]=0xFAC2FA, [0xFFC5C5]=0xFBC9FB,
      [0xFFC5CD]=0xFBC9FB, [0xFFC5D5]=0xFBC9FB, [0xFFCDD5]=0xFBD1FB, [0xFFCDDE]=0xFBD1FB,
      [0xFFD5DE]=0xFCD8FC, [0xFFD5E6]=0xFCD8FC, [0xFFDEDE]=0xFDE0FD, [0xFFDEE6]=0xFDE0FD,
      [0xFFE6E6]=0xFDE8FD, [0xFFE6EE]=0xFDE8FD,
    },
  },
  [40] = {
    name = "wigglytuff",
    hueRange = { min = -40, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFCDDE,
    -- Stadium ships a real alternate texture for this one; 409
    -- colours move, every other colour stays exactly as it was.
    lut = {
      [0x080008]=0x070107, [0x082018]=0x152206, [0x082920]=0x1A2B06, [0x083931]=0x233D04,
      [0x100808]=0x0F090F, [0x103931]=0x273C0D, [0x104139]=0x2B450C, [0x104A39]=0x304E0C,
      [0x183939]=0x2A3B16, [0x184139]=0x2F4415, [0x184A39]=0x344E14, [0x184A41]=0x344E14,
      [0x18524A]=0x385614, [0x185A4A]=0x3D5F13, [0x204141]=0x32431E, [0x204A41]=0x374D1D,
      [0x204A4A]=0x374D1D, [0x20524A]=0x3C561C, [0x205A52]=0x405E1C, [0x206252]=0x45671B,
      [0x20625A]=0x45671B, [0x294A4A]=0x3B4C27, [0x29524A]=0x405526, [0x295252]=0x405526,
      [0x295A52]=0x445E25, [0x295A5A]=0x445E25, [0x296252]=0x496625, [0x29625A]=0x496625,
      [0x296A5A]=0x4D6F24, [0x29736A]=0x527923, [0x31524A]=0x43542F, [0x315252]=0x43542F,
      [0x315A52]=0x485D2E, [0x315A5A]=0x485D2E, [0x31625A]=0x4C662D, [0x316A62]=0x516E2D,
      [0x317362]=0x56782C, [0x31736A]=0x56782C, [0x317B6A]=0x5A812B, [0x317B73]=0x5A812B,
      [0x395252]=0x475437, [0x395A52]=0x4B5C37, [0x395A5A]=0x4B5C37, [0x395A62]=0x506536,
      [0x39625A]=0x506536, [0x396262]=0x506536, [0x396A62]=0x546E35, [0x39736A]=0x597735,
      [0x397B6A]=0x5E8034, [0x397B73]=0x5E8034, [0x398373]=0x628933, [0x398B7B]=0x679133,
      [0x415A5A]=0x4F5C3F, [0x416262]=0x53643F, [0x416A6A]=0x586D3E, [0x41736A]=0x5D773D,
      [0x417373]=0x5D773D, [0x417B6A]=0x617F3D, [0x417B73]=0x617F3D, [0x418373]=0x66883C,
      [0x41837B]=0x66883C, [0x418B7B]=0x6A913B, [0x418B83]=0x6A913B, [0x419483]=0x6F9A3B,
      [0x41A494]=0x78AB3A, [0x4A3139]=0x483348, [0x4A6A6A]=0x5C6C48, [0x4A6A73]=0x617647,
      [0x4A7373]=0x617647, [0x4A7B73]=0x657F46, [0x4A837B]=0x6A8746, [0x4A8B83]=0x6E9045,
      [0x4A9483]=0x739A44, [0x4A948B]=0x739A44, [0x4A9C8B]=0x78A244, [0x4AAC9C]=0x81B343,
      [0x523139]=0x503350, [0x523141]=0x503350, [0x523941]=0x503B50, [0x527373]=0x647550,
      [0x52737B]=0x697E4F, [0x527B7B]=0x697E4F, [0x528383]=0x6D874E, [0x52948B]=0x77994D,
      [0x529C8B]=0x7BA24C, [0x529C94]=0x7BA24C, [0x52A494]=0x80AA4C, [0x52A49C]=0x80AA4C,
      [0x52AC9C]=0x84B34B, [0x5A3941]=0x583B58, [0x5A394A]=0x583B58, [0x5A414A]=0x584358,
      [0x5A4152]=0x584358, [0x5A737B]=0x6C7D58, [0x5A7B7B]=0x6C7D58, [0x5A7B83]=0x718657,
      [0x5A8383]=0x718657, [0x5A948B]=0x7A9856, [0x5A9C94]=0x7FA155, [0x5AA494]=0x83AA54,
      [0x5AA49C]=0x83AA54, [0x5AAC9C]=0x88B254, [0x5AACA4]=0x88B254, [0x62394A]=0x5F3C5F,
      [0x62414A]=0x604360, [0x62A49C]=0x87A95D, [0x62AC9C]=0x8BB25C, [0x62B4A4]=0x90BA5C,
      [0x62B4AC]=0x90BA5C, [0x6A414A]=0x674467, [0x6A948B]=0x819767, [0x6AB4A4]=0x93BA64,
      [0x6AB4AC]=0x93BA64, [0x6ABDAC]=0x98C364, [0x6ABDB4]=0x98C364, [0x6AC5B4]=0x9DCC63,
      [0x73525A]=0x715471, [0x73C5B4]=0xA1CB6D, [0x73C5BD]=0xA1CB6D, [0x7B4A5A]=0x774E77,
      [0x7B525A]=0x785578, [0x7B5A62]=0x795C79, [0x7B9CA4]=0x92A778, [0x7BB4AC]=0x9BB877,
      [0x7BBDB4]=0xA0C276, [0x7BC5B4]=0xA4CB75, [0x7BC5BD]=0xA4CB75, [0x7BCDBD]=0xA9D375,
      [0x7BCDC5]=0xA9D375, [0x7BD5C5]=0xADDC74, [0x83525A]=0x7F567F, [0x835262]=0x7F567F,
      [0x835A62]=0x805D80, [0x835A6A]=0x805D80, [0x839CA4]=0x95A681, [0x83ACA4]=0x9AAF80,
      [0x83C5BD]=0xA8CA7E, [0x83CDC5]=0xACD37D, [0x83D5C5]=0xB1DB7D, [0x83D5CD]=0xB1DB7D,
      [0x8B5262]=0x875687, [0x8B5A62]=0x875E87, [0x8B5A6A]=0x875E87, [0x8B626A]=0x886588,
      [0x8BA4AC]=0x9DAE89, [0x8BB4AC]=0xA2B788, [0x8BB4B4]=0xA2B788, [0x8BCDC5]=0xB0D286,
      [0x8BD5CD]=0xB4DB85, [0x945A6A]=0x905E90, [0x94626A]=0x906690, [0x946273]=0x906690,
      [0x946A73]=0x916D91, [0x946A7B]=0x916D91, [0x94ACB4]=0xA6B692, [0x94B4AC]=0xA6B692,
      [0x94B4B4]=0xA6B692, [0x94BDB4]=0xABC091, [0x94D5CD]=0xB8DA8F, [0x94DED5]=0xBDE48E,
      [0x9C6273]=0x986698, [0x9C6A73]=0x986E98, [0x9C6A7B]=0x986E98, [0x9C737B]=0x997699,
      [0x9C7383]=0x997699, [0x9CB4BD]=0xAEBF9A, [0x9CBDBD]=0xAEBF9A, [0x9CC5BD]=0xB3C899,
      [0x9CC5C5]=0xB3C899, [0x9CDED5]=0xC1E397, [0x9CE6DE]=0xC5EC96, [0xA44141]=0x9D489D,
      [0xA46A7B]=0xA06EA0, [0xA4737B]=0xA077A0, [0xA47383]=0xA077A0, [0xA47B83]=0xA17EA1,
      [0xA47B8B]=0xA17EA1, [0xA4838B]=0xA285A2, [0xA4BDBD]=0xB2BFA2, [0xA4E6DE]=0xC9EB9F,
      [0xA4EEDE]=0xCDF49E, [0xAC4A4A]=0xA551A5, [0xAC4A52]=0xA551A5, [0xAC525A]=0xA559A5,
      [0xAC626A]=0xA668A6, [0xAC7383]=0xA877A8, [0xAC838B]=0xA986A9, [0xAC8394]=0xA986A9,
      [0xAC8B94]=0xAA8DAA, [0xACBDC5]=0xBAC7AA, [0xACC5C5]=0xBAC7AA, [0xACCDCD]=0xBECFAA,
      [0xACEEE6]=0xD1F3A7, [0xB44A52]=0xAC52AC, [0xB45252]=0xAD59AD, [0xB45A5A]=0xAD61AD,
      [0xB45A62]=0xAD61AD, [0xB46A73]=0xAE70AE, [0xB46A7B]=0xAE70AE, [0xB47373]=0xAF78AF,
      [0xB4737B]=0xAF78AF, [0xB47B8B]=0xB07FB0, [0xB4838B]=0xB087B0, [0xB48394]=0xB087B0,
      [0xB48B94]=0xB18EB1, [0xB48B9C]=0xB18EB1, [0xB4949C]=0xB296B2, [0xB4EEE6]=0xD4F2B0,
      [0xB4F6EE]=0xD9FBAF, [0xBD525A]=0xB55AB5, [0xBD5A62]=0xB661B6, [0xBD6262]=0xB669B6,
      [0xBD626A]=0xB669B6, [0xBD6A6A]=0xB770B7, [0xBD737B]=0xB779B7, [0xBD7B7B]=0xB880B8,
      [0xBD7B83]=0xB880B8, [0xBD838B]=0xB987B9, [0xBD8394]=0xB987B9, [0xBD8B94]=0xB98FB9,
      [0xBD949C]=0xBA97BA, [0xBD94A4]=0xBA97BA, [0xBDD5D5]=0xCAD7BB, [0xBDEEEE]=0xD8F2B9,
      [0xBDF6EE]=0xDDFAB9, [0xC55A62]=0xBD62BD, [0xC5626A]=0xBE69BE, [0xC56A6A]=0xBE71BE,
      [0xC56A73]=0xBE71BE, [0xC57373]=0xBF79BF, [0xC5737B]=0xBF79BF, [0xC57B7B]=0xBF81BF,
      [0xC57B83]=0xBF81BF, [0xC58383]=0xC088C0, [0xC5838B]=0xC088C0, [0xC58B9C]=0xC18FC1,
      [0xC5949C]=0xC198C1, [0xC594A4]=0xC198C1, [0xC59CA4]=0xC29FC2, [0xC5ACB4]=0xC3AEC3,
      [0xC5CDD5]=0xCED6C4, [0xC5D5D5]=0xCED6C4, [0xC5D5DE]=0xD3E0C3, [0xC5DEDE]=0xD3E0C3,
      [0xC5F6EE]=0xE0FAC1, [0xC5F6F6]=0xE0FAC1, [0xC5FFF6]=0xE5FFC5, [0xCD6A73]=0xC671C6,
      [0xCD7373]=0xC67AC6, [0xCD737B]=0xC67AC6, [0xCD7B7B]=0xC781C7, [0xCD7B83]=0xC781C7,
      [0xCD8383]=0xC789C7, [0xCD838B]=0xC789C7, [0xCD8B8B]=0xC890C8, [0xCD8B94]=0xC890C8,
      [0xCD949C]=0xC998C9, [0xCD94A4]=0xC998C9, [0xCD9CA4]=0xC9A0C9, [0xCD9CAC]=0xC9A0C9,
      [0xCDA4AC]=0xCAA7CA, [0xCDB4BD]=0xCBB6CB, [0xCDD5DE]=0xD6DFCC, [0xCDDEDE]=0xD6DFCC,
      [0xCDF6EE]=0xE4F9CA, [0xCDF6F6]=0xE4F9CA, [0xCDFFF6]=0xE8FFCD, [0xD5737B]=0xCE7ACE,
      [0xD57B83]=0xCE82CE, [0xD58383]=0xCF89CF, [0xD5838B]=0xCF89CF, [0xD58B8B]=0xCF91CF,
      [0xD58B94]=0xCF91CF, [0xD58B9C]=0xCF91CF, [0xD59494]=0xD099D0, [0xD5949C]=0xD099D0,
      [0xD594A4]=0xD099D0, [0xD59C9C]=0xD1A0D1, [0xD59CA4]=0xD1A0D1, [0xD59CAC]=0xD1A0D1,
      [0xD5A4AC]=0xD1A8D1, [0xD5A4B4]=0xD1A8D1, [0xD5ACB4]=0xD2AFD2, [0xD5B4BD]=0xD3B6D3,
      [0xD5BDBD]=0xD3BFD3, [0xD5BDC5]=0xD3BFD3, [0xD5DEE6]=0xDEE7D4, [0xD5E6E6]=0xDEE7D4,
      [0xD5FFFF]=0xECFFD5, [0xDE737B]=0xD67BD6, [0xDE8383]=0xD78AD7, [0xDE838B]=0xD78AD7,
      [0xDE8394]=0xD78AD7, [0xDE8B8B]=0xD891D8, [0xDE8B94]=0xD891D8, [0xDE8B9C]=0xD891D8,
      [0xDE9494]=0xD89AD8, [0xDE949C]=0xD89AD8, [0xDE94A4]=0xD89AD8, [0xDE9C9C]=0xD9A1D9,
      [0xDE9CA4]=0xD9A1D9, [0xDEA4A4]=0xDAA8DA, [0xDEA4AC]=0xDAA8DA, [0xDEA4B4]=0xDAA8DA,
      [0xDEACB4]=0xDAB0DA, [0xDEACBD]=0xDAB0DA, [0xDEB4BD]=0xDBB7DB, [0xDEBDC5]=0xDCBFDC,
      [0xDEC5CD]=0xDCC7DC, [0xDECDCD]=0xDDCEDD, [0xDEF6F6]=0xEBF8DC, [0xDEFFF6]=0xF0FFDE,
      [0xDEFFFF]=0xF0FFDE, [0xE67B7B]=0xDE83DE, [0xE6838B]=0xDF8ADF, [0xE68B94]=0xDF92DF,
      [0xE68B9C]=0xDF92DF, [0xE69494]=0xE09AE0, [0xE6949C]=0xE09AE0, [0xE69C9C]=0xE0A2E0,
      [0xE69CA4]=0xE0A2E0, [0xE69CAC]=0xE0A2E0, [0xE6A4A4]=0xE1A9E1, [0xE6A4AC]=0xE1A9E1,
      [0xE6A4B4]=0xE1A9E1, [0xE6ACAC]=0xE2B0E2, [0xE6ACB4]=0xE2B0E2, [0xE6ACBD]=0xE2B0E2,
      [0xE6B4B4]=0xE2B8E2, [0xE6B4BD]=0xE2B8E2, [0xE6B4C5]=0xE2B8E2, [0xE6BDC5]=0xE3C0E3,
      [0xE6BDCD]=0xE3C0E3, [0xE6C5CD]=0xE4C7E4, [0xE6E6EE]=0xEAEFE5, [0xE6EEEE]=0xEAEFE5,
      [0xE6F6F6]=0xEFF7E5, [0xE6FFFF]=0xF4FFE6, [0xEE8B8B]=0xE792E7, [0xEE9494]=0xE79BE7,
      [0xEE949C]=0xE79BE7, [0xEE9C9C]=0xE8A2E8, [0xEE9CA4]=0xE8A2E8, [0xEEA4A4]=0xE8AAE8,
      [0xEEA4AC]=0xE8AAE8, [0xEEA4B4]=0xE8AAE8, [0xEEACAC]=0xE9B1E9, [0xEEACB4]=0xE9B1E9,
      [0xEEACBD]=0xE9B1E9, [0xEEB4BD]=0xEAB8EA, [0xEEB4C5]=0xEAB8EA, [0xEEBDC5]=0xEAC1EA,
      [0xEEBDCD]=0xEAC1EA, [0xEEC5CD]=0xEBC8EB, [0xEEC5D5]=0xEBC8EB, [0xEECDD5]=0xECCFEC,
      [0xEED5D5]=0xECD7EC, [0xEED5DE]=0xECD7EC, [0xEEEEF6]=0xF2F7ED, [0xEEF6F6]=0xF2F7ED,
      [0xEEFFFF]=0xF7FFEE, [0xF68383]=0xED8CED, [0xF68B94]=0xEE93EE, [0xF69C9C]=0xEFA3EF,
      [0xF69CA4]=0xEFA3EF, [0xF6A4A4]=0xF0AAF0, [0xF6A4AC]=0xF0AAF0, [0xF6ACAC]=0xF0B2F0,
      [0xF6B4B4]=0xF1B9F1, [0xF6B4BD]=0xF1B9F1, [0xF6B4C5]=0xF1B9F1, [0xF6BDC5]=0xF2C1F2,
      [0xF6BDCD]=0xF2C1F2, [0xF6C5CD]=0xF2C9F2, [0xF6C5D5]=0xF2C9F2, [0xF6CDD5]=0xF3D0F3,
      [0xF6D5D5]=0xF4D7F4, [0xF6D5DE]=0xF4D7F4, [0xF6FFFF]=0xFBFFF6, [0xFF8383]=0xF68CF6,
      [0xFF8B8B]=0xF694F6, [0xFF9494]=0xF79CF7, [0xFF949C]=0xF79CF7, [0xFF9C9C]=0xF8A3F8,
      [0xFF9CA4]=0xF8A3F8, [0xFFA4A4]=0xF8ABF8, [0xFFA4AC]=0xF8ABF8, [0xFFACAC]=0xF9B2F9,
      [0xFFACB4]=0xF9B2F9, [0xFFB4B4]=0xF9BAF9, [0xFFBDBD]=0xFAC2FA, [0xFFBDCD]=0xFAC2FA,
      [0xFFC5C5]=0xFBC9FB, [0xFFC5CD]=0xFBC9FB, [0xFFC5D5]=0xFBC9FB, [0xFFCDCD]=0xFBD1FB,
      [0xFFCDD5]=0xFBD1FB, [0xFFCDDE]=0xFBD1FB, [0xFFD5D5]=0xFCD8FC, [0xFFD5DE]=0xFCD8FC,
      [0xFFD5E6]=0xFCD8FC, [0xFFDEDE]=0xFDE0FD, [0xFFDEE6]=0xFDE0FD, [0xFFE6E6]=0xFDE8FD,
      [0xFFE6EE]=0xFDE8FD, [0xFFEEEE]=0xFEEFFE, [0xFFEEF6]=0xFEEFFE, [0xFFF6F6]=0xFEF7FE,
      [0xFFF6FF]=0xFEF7FE,
    },
  },
  [41] = {
    name = "zubat",
    hueRange = { min = -30, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x73DEF6,
    slide = { h = -110, l = -1, s = -2 },
  },
  [42] = {
    name = "golbat",
    hueRange = { min = -25, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x29ACE6,
    slide = { h = -63, l = -6, s = -4 },
  },
  [43] = {
    name = "oddish",
    hueRange = { min = -40, max = 70 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x626A83,
    slide = { h = -50, l = 2, s = 3 },
  },
  [44] = {
    name = "gloom",
    hueRange = { min = -40, max = 65 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x626A83,
    slide = { h = 30, l = 3, s = 1 },
  },
  [45] = {
    name = "vileplume",
    hueRange = { min = -25, max = 60 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x626A83,
    slide = { h = 50, l = 3, s = 1 },
  },
  [46] = {
    name = "paras",
    hueRange = { min = -20, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xC5E6FF,
    slide = { h = 25, l = -3, s = 3 },
  },
  [47] = {
    name = "parasect",
    hueRange = { min = -20, max = 35 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xEE5231,
    slide = { h = 40, l = -4, s = 6 },
  },
  [48] = {
    name = "venonat",
    hueRange = { min = -60, max = 60 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x4A3952,
    slide = { h = -90, l = 0, s = 0 },
  },
  [49] = {
    name = "venomoth",
    hueRange = { min = -60, max = 100 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xF6C5E6,
    slide = { h = -90, l = 0, s = 1 },
  },
  [50] = {
    name = "diglett",
    hueRange = { min = -20, max = 35 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xBD6239,
    slide = { h = -50, l = 1, s = -2 },
  },
  [51] = {
    name = "dugtrio",
    hueRange = { min = -20, max = 35 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xBD6239,
    slide = { h = -50, l = 1, s = -2 },
  },
  [52] = {
    name = "meowth",
    hueRange = { min = -40, max = 35 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xF6EEAC,
    slide = { h = -55, l = 2, s = 0 },
  },
  [53] = {
    name = "persian",
    hueRange = { min = -20, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFE6BD,
    slide = { h = -30, l = 0, s = -2 },
  },
  [54] = {
    name = "psyduck",
    hueRange = { min = -20, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFDE29,
    slide = { h = -142, l = 2, s = -2 },
  },
  [55] = {
    name = "golduck",
    hueRange = { min = -60, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x8B9CAC,
    slide = { h = 20, l = 0, s = 3 },
  },
  [56] = {
    name = "mankey",
    hueRange = { min = -35, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFEEAC,
    slide = { h = 105, l = -1, s = -3 },
  },
  [57] = {
    name = "primeape",
    hueRange = { min = -35, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFD59C,
    slide = { h = -50, l = 1, s = -3 },
  },
  [58] = {
    name = "growlithe",
    hueRange = { min = -35, max = 10 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xEEB420,
    slide = { h = 20, l = 0, s = 2 },
  },
  [59] = {
    name = "arcanine",
    hueRange = { min = -30, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xF69429,
    slide = { h = 25, l = 1, s = -3 },
  },
  [60] = {
    name = "poliwag",
    hueRange = { min = -50, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x6A7BA4,
    slide = { h = -20, l = 0, s = 3 },
  },
  [61] = {
    name = "poliwhirl",
    hueRange = { min = -50, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x6A7BA4,
    slide = { h = 20, l = -2, s = 2 },
  },
  [62] = {
    name = "poliwrath",
    hueRange = { min = -50, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x6A7BA4,
    slide = { h = -58, l = -2, s = 3 },
  },
  [63] = {
    name = "abra",
    hueRange = { min = -20, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xD5A420,
    slide = { h = 20, l = 1, s = -1 },
  },
  [64] = {
    name = "kadabra",
    hueRange = { min = -30, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xEECD5A,
    slide = { h = 10, l = 1, s = 1 },
  },
  [65] = {
    name = "alakazam",
    hueRange = { min = -30, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xEECD5A,
    slide = { h = 20, l = -2, s = 1 },
  },
  [66] = {
    name = "machop",
    hueRange = { min = -40, max = 60 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xACD5BD,
    slide = { h = 100, l = 0, s = 0 },
  },
  [67] = {
    name = "machoke",
    hueRange = { min = -70, max = 60 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x949CBD,
    slide = { h = -120, l = 1, s = -2 },
  },
  [68] = {
    name = "machamp",
    hueRange = { min = -70, max = 80 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xACD5C5,
    slide = { h = 100, l = 0, s = -2 },
  },
  [69] = {
    name = "bellsprout",
    hueRange = { min = -15, max = 15 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFFF18,
    slide = { h = -25, l = 0, s = -3 },
  },
  [70] = {
    name = "weepinbell",
    hueRange = { min = -25, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xF8F860,
    slide = { h = -75, l = -1, s = -3 },
  },
  [71] = {
    name = "victreebel",
    hueRange = { min = -30, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFFF62,
    slide = { h = 40, l = -2, s = -3 },
  },
  [72] = {
    name = "tentacool",
    hueRange = { min = -40, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x4AC5C5,
    slide = { h = 50, l = 2, s = 2 },
  },
  [73] = {
    name = "tentacruel",
    hueRange = { min = -40, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x4AC5C5,
    slide = { h = 50, l = 2, s = 2 },
  },
  [74] = {
    name = "geodude",
    hueRange = { min = -180, max = 180 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x73735A,
    slide = { h = -70, l = 0, s = 0 },
  },
  [75] = {
    name = "graveler",
    hueRange = { min = -180, max = 180 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x525239,
    slide = { h = -55, l = 0, s = 0 },
  },
  [76] = {
    name = "golem",
    hueRange = { min = -50, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x836A52,
    slide = { h = -55, l = 0, s = -2 },
  },
  [77] = {
    name = "ponyta",
    hueRange = { min = -25, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFFF83,
    slide = { h = 40, l = 2, s = -1 },
  },
  [78] = {
    name = "rapidash",
    hueRange = { min = -25, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFFF83,
    slide = { h = 40, l = 2, s = -1 },
  },
  [79] = {
    name = "slowpoke",
    hueRange = { min = -40, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFF8B94,
    slide = { h = -90, l = -6, s = -3 },
  },
  [80] = {
    name = "slowbro",
    hueRange = { min = -40, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xA4ACA4,
    slide = { h = -75, l = -4, s = -2 },
  },
  [81] = {
    name = "magnemite",
    hueRange = { min = -180, max = 180 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x5A5A5A,
    slide = { h = -30, l = 2, s = -4 },
  },
  [82] = {
    name = "magneton",
    hueRange = { min = -180, max = 180 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x5A5A5A,
    slide = { h = -30, l = 2, s = -4 },
  },
  [83] = {
    name = "farfetchd",
    hueRange = { min = -30, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xB4946A,
    slide = { h = 15, l = 1, s = 2 },
  },
  [84] = {
    name = "doduo",
    hueRange = { min = -10, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xBD6200,
    slide = { h = 31, l = 1, s = 2 },
  },
  [85] = {
    name = "dodrio",
    hueRange = { min = -10, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xB45A00,
    slide = { h = 31, l = 1, s = 2 },
  },
  [86] = {
    name = "seel",
    hueRange = { min = -40, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xE67373,
    slide = { h = -180, l = 3, s = -4 },
  },
  [87] = {
    name = "dewgong",
    hueRange = { min = -10, max = 10 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xDEEEDE,
    slide = { h = -180, l = 3, s = -4 },
  },
  [88] = {
    name = "grimer",
    hueRange = { min = -180, max = 180 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x5A4A5A,
    slide = { h = 125, l = -1, s = 1 },
  },
  [89] = {
    name = "muk",
    hueRange = { min = -180, max = 180 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x5A4A5A,
    slide = { h = -115, l = 0, s = 1 },
  },
  [90] = {
    name = "shellder",
    hueRange = { min = -70, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x8B73C5,
    slide = { h = 120, l = 0, s = 0 },
  },
  [91] = {
    name = "cloyster",
    hueRange = { min = -70, max = 60 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x29104A,
    slide = { h = 140, l = 0, s = 0 },
  },
  [92] = {
    name = "gastly",
    hueRange = { min = -80, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x201029,
    slide = { h = -124, l = 0, s = 0 },
  },
  [93] = {
    name = "haunter",
    hueRange = { min = -70, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x6A418B,
    slide = { h = -50, l = -2, s = -2 },
  },
  [94] = {
    name = "gengar",
    hueRange = { min = -90, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x5A3962,
    slide = { h = -55, l = -2, s = -1 },
  },
  [95] = {
    name = "onix",
    hueRange = { min = -180, max = 180 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xA4A4BD,
    slide = { h = -171, l = -3, s = 0 },
  },
  [96] = {
    name = "drowzee",
    hueRange = { min = -10, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFBD00,
    slide = { h = -110, l = 4, s = -4 },
  },
  [97] = {
    name = "hypno",
    hueRange = { min = -15, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xE6BD18,
    slide = { h = -80, l = 1, s = -3 },
  },
  [98] = {
    name = "krabby",
    hueRange = { min = -20, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xF63100,
    slide = { h = 40, l = -1, s = 0 },
  },
  [99] = {
    name = "kingler",
    hueRange = { min = -20, max = 25 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xBD6A31,
    slide = { h = 35, l = -1, s = 2 },
  },
  [100] = {
    name = "voltorb",
    hueRange = { min = -70, max = 10 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x8B3939,
    slide = { h = -95, l = 0, s = 0 },
  },
  [101] = {
    name = "electrode",
    hueRange = { min = -70, max = 10 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xBD4A4A,
    slide = { h = -95, l = 0, s = 0 },
  },
  [102] = {
    name = "exeggcute",
    hueRange = { min = -50, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xF6B4BD,
    slide = { h = 70, l = 0, s = 0 },
  },
  [103] = {
    name = "exeggutor",
    hueRange = { min = -30, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFEE83,
    slide = { h = -60, l = 2, s = -3 },
  },
  [104] = {
    name = "cubone",
    hueRange = { min = -25, max = 5 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xDEAC39,
    slide = { h = 160, l = 2, s = -5 },
  },
  [105] = {
    name = "marowak",
    hueRange = { min = -25, max = 5 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xDED5C5,
    slide = { h = 160, l = 2, s = -5 },
  },
  [106] = {
    name = "hitmonlee",
    hueRange = { min = -20, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x94524A,
    slide = { h = 70, l = 0, s = -2 },
  },
  [107] = {
    name = "hitmonchan",
    hueRange = { min = -20, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xA4836A,
    slide = { h = -145, l = 1, s = -1 },
  },
  [108] = {
    name = "lickitung",
    hueRange = { min = -50, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xF6A4A4,
    slide = { h = 60, l = -1, s = 1 },
  },
  [109] = {
    name = "koffing",
    hueRange = { min = -60, max = 90 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x73418B,
    slide = { h = -80, l = -1, s = 3 },
  },
  [110] = {
    name = "weezing",
    hueRange = { min = -60, max = 90 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x836A83,
    slide = { h = -90, l = 0, s = 1 },
  },
  [111] = {
    name = "rhyhorn",
    hueRange = { min = -180, max = 180 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xA4ACBD,
    slide = { h = 150, l = -1, s = 1 },
  },
  [112] = {
    name = "rhydon",
    hueRange = { min = -180, max = 180 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xA4A4AC,
    slide = { h = 58, l = 1, s = 1 },
  },
  [113] = {
    name = "chansey",
    hueRange = { min = -50, max = 60 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFD5E6,
    slide = { h = 80, l = 0, s = 0 },
  },
  [114] = {
    name = "tangela",
    hueRange = { min = -40, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xEE5A73,
    slide = { h = -120, l = 0, s = 0 },
  },
  [115] = {
    name = "kangaskhan",
    hueRange = { min = -30, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x836A4A,
    slide = { h = -176, l = 0, s = -2 },
  },
  [116] = {
    name = "horsea",
    hueRange = { min = -40, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x83B4DE,
    slide = { h = -70, l = 0, s = -1 },
  },
  [117] = {
    name = "seadra",
    hueRange = { min = -30, max = 35 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x5AB4DE,
    slide = { h = -65, l = 2, s = 1 },
  },
  [118] = {
    name = "goldeen",
    hueRange = { min = -60, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xF6F6D5,
    slide = { h = 50, l = 0, s = 3 },
  },
  [119] = {
    name = "seaking",
    hueRange = { min = -50, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xB43918,
    slide = { h = 40, l = 1, s = 3 },
  },
  [120] = {
    name = "staryu",
    hueRange = { min = -10, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xE14254,
    slide = { h = -176, l = 0, s = 0 },
  },
  [121] = {
    name = "starmie",
    hueRange = { min = -40, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFF3888,
    slide = { h = -110, l = 0, s = 0 },
  },
  [122] = {
    name = "mr_mime",
    hueRange = { min = -30, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFC5C5,
    slide = { h = 30, l = -2, s = 2 },
  },
  [123] = {
    name = "scyther",
    hueRange = { min = -30, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x83C56A,
    slide = { h = -110, l = 0, s = 0 },
  },
  [124] = {
    name = "jynx",
    hueRange = { min = -10, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x525A73,
    slide = { h = 30, l = 0, s = 3 },
  },
  [125] = {
    name = "electabuzz",
    hueRange = { min = -20, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFEE00,
    slide = { h = -40, l = 2, s = -2 },
  },
  [126] = {
    name = "magmar",
    hueRange = { min = -15, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xEE3918,
    slide = { h = -60, l = 1, s = -2 },
  },
  [127] = {
    name = "pinsir",
    hueRange = { min = -60, max = 130 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x836A62,
    slide = { h = -150, l = 0, s = 0 },
  },
  [128] = {
    name = "tauros",
    hueRange = { min = -10, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xC59429,
    slide = { h = -20, l = 4, s = -2 },
  },
  [129] = {
    name = "magikarp",
    hueRange = { min = -30, max = 25 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xE64A31,
    slide = { h = 50, l = -1, s = 2 },
  },
  [130] = {
    name = "gyarados",
    hueRange = { min = -20, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x62BDEE,
    -- Stadium ships a real alternate texture for this one; 481
    -- colours move, every other colour stays exactly as it was.
    lut = {
      [0x000008]=0x070000, [0x000808]=0x070000, [0x000810]=0x0D0100, [0x001010]=0x0D0100,
      [0x001018]=0x140100, [0x080008]=0x070000, [0x080010]=0x0D0100, [0x080810]=0x0D0707,
      [0x080818]=0x140707, [0x080820]=0x1A0807, [0x080829]=0x220807, [0x080831]=0x280907,
      [0x080839]=0x2F0907, [0x081010]=0x0D0707, [0x081018]=0x140707, [0x081020]=0x1A0807,
      [0x081031]=0x280907, [0x081039]=0x2F0907, [0x081041]=0x350A07, [0x081818]=0x140707,
      [0x081820]=0x1A0807, [0x081829]=0x220807, [0x081841]=0x350A07, [0x08184A]=0x3D0A07,
      [0x082029]=0x220807, [0x082031]=0x280907, [0x082039]=0x2F0907, [0x082041]=0x350A07,
      [0x08204A]=0x3D0A07, [0x082052]=0x430B07, [0x082931]=0x280907, [0x082941]=0x350A07,
      [0x082952]=0x430B07, [0x08295A]=0x4A0B07, [0x082962]=0x500B07, [0x083131]=0x280907,
      [0x083141]=0x350A07, [0x083152]=0x430B07, [0x08315A]=0x4A0B07, [0x083162]=0x500B07,
      [0x08394A]=0x3D0A07, [0x08395A]=0x4A0B07, [0x083962]=0x500B07, [0x08396A]=0x570C07,
      [0x083973]=0x5E0C07, [0x084162]=0x500B07, [0x08416A]=0x570C07, [0x084173]=0x5E0C07,
      [0x08417B]=0x650D07, [0x084A6A]=0x570C07, [0x084A73]=0x5E0C07, [0x084A7B]=0x650D07,
      [0x085273]=0x5E0C07, [0x08527B]=0x650D07, [0x085283]=0x6B0D07, [0x08528B]=0x720E07,
      [0x085A8B]=0x720E07, [0x085A94]=0x790E07, [0x086294]=0x790E07, [0x08629C]=0x800F07,
      [0x086A9C]=0x800F07, [0x100010]=0x0D0100, [0x100018]=0x140100, [0x100810]=0x0D0707,
      [0x101820]=0x1A0E0D, [0x102029]=0x220E0D, [0x102031]=0x280F0D, [0x102931]=0x280F0D,
      [0x102939]=0x2F0F0D, [0x103139]=0x2F0F0D, [0x103141]=0x35100D, [0x104A5A]=0x4A110D,
      [0x105273]=0x5E130D, [0x105A8B]=0x72140D, [0x10628B]=0x72140D, [0x106294]=0x79140D,
      [0x106A9C]=0x80150D, [0x106AA4]=0x86150D, [0x1073A4]=0x86150D, [0x180818]=0x140707,
      [0x180820]=0x1A0807, [0x181018]=0x140E0D, [0x182939]=0x2F1514, [0x183139]=0x2F1514,
      [0x183141]=0x351614, [0x18314A]=0x3D1614, [0x183941]=0x351614, [0x18394A]=0x3D1614,
      [0x183952]=0x431714, [0x184152]=0x431714, [0x18415A]=0x4A1714, [0x185262]=0x501814,
      [0x185A7B]=0x651914, [0x186A94]=0x791A14, [0x18739C]=0x801B14, [0x1873A4]=0x861B14,
      [0x1873AC]=0x8D1C14, [0x187BAC]=0x8D1C14, [0x200820]=0x1A0807, [0x200829]=0x220807,
      [0x201020]=0x1A0E0D, [0x201029]=0x220E0D, [0x201831]=0x281514, [0x203941]=0x351C1A,
      [0x20394A]=0x3D1D1A, [0x203952]=0x431D1A, [0x20414A]=0x3D1D1A, [0x204152]=0x431D1A,
      [0x20415A]=0x4A1D1A, [0x204A5A]=0x4A1D1A, [0x204A62]=0x501E1A, [0x205262]=0x501E1A,
      [0x20526A]=0x571E1A, [0x206273]=0x5E1F1A, [0x20627B]=0x651F1A, [0x206283]=0x6B201A,
      [0x20739C]=0x80211A, [0x207BA4]=0x86211A, [0x207BAC]=0x8D221A, [0x207BB4]=0x94221A,
      [0x2083B4]=0x94221A, [0x290829]=0x220807, [0x291029]=0x220E0D, [0x291831]=0x281514,
      [0x29314A]=0x3D2322, [0x293941]=0x352322, [0x29394A]=0x3D2322, [0x294152]=0x432422,
      [0x294A5A]=0x4A2422, [0x294A62]=0x502522, [0x295262]=0x502522, [0x29526A]=0x572522,
      [0x295273]=0x5E2622, [0x295A6A]=0x572522, [0x295A73]=0x5E2622, [0x295A7B]=0x652622,
      [0x296273]=0x5E2622, [0x29627B]=0x652622, [0x296A8B]=0x722722, [0x297394]=0x792722,
      [0x29739C]=0x802822, [0x297BA4]=0x862822, [0x297BAC]=0x8D2922, [0x2983B4]=0x942922,
      [0x2983BD]=0x9B2A22, [0x298BBD]=0x9B2A22, [0x311031]=0x280F0D, [0x311039]=0x2F0F0D,
      [0x311839]=0x2F1514, [0x312031]=0x281B1A, [0x312039]=0x2F1C1A, [0x312941]=0x352322,
      [0x313152]=0x432A28, [0x313952]=0x432A28, [0x31415A]=0x4A2A28, [0x314A5A]=0x4A2A28,
      [0x314A62]=0x502B28, [0x315262]=0x502B28, [0x31526A]=0x572B28, [0x315A6A]=0x572B28,
      [0x315A73]=0x5E2C28, [0x316273]=0x5E2C28, [0x31627B]=0x652C28, [0x316283]=0x6B2D28,
      [0x316A7B]=0x652C28, [0x316A83]=0x6B2D28, [0x316A8B]=0x722D28, [0x31738B]=0x722D28,
      [0x317394]=0x792E28, [0x31739C]=0x802E28, [0x317B9C]=0x802E28, [0x317BA4]=0x862E28,
      [0x3183A4]=0x862E28, [0x3183AC]=0x8D2F28, [0x3183B4]=0x942F28, [0x318BB4]=0x942F28,
      [0x318BBD]=0x9B3028, [0x318BC5]=0xA23028, [0x3194C5]=0xA23028, [0x391841]=0x351614,
      [0x392039]=0x2F1C1A, [0x39395A]=0x4A312F, [0x394152]=0x43302F, [0x39525A]=0x4A312F,
      [0x395262]=0x50312F, [0x39526A]=0x57312F, [0x395A62]=0x50312F, [0x395A6A]=0x57312F,
      [0x396273]=0x5E322F, [0x39627B]=0x65322F, [0x396A7B]=0x65322F, [0x396A83]=0x6B332F,
      [0x396A8B]=0x72332F, [0x39738B]=0x72332F, [0x397394]=0x79342F, [0x39739C]=0x80342F,
      [0x397B8B]=0x72332F, [0x397B94]=0x79342F, [0x397B9C]=0x80342F, [0x397BA4]=0x86352F,
      [0x3983A4]=0x86352F, [0x3983AC]=0x8D352F, [0x3983B4]=0x94352F, [0x398BB4]=0x94352F,
      [0x398BBD]=0x9B362F, [0x3994BD]=0x9B362F, [0x3994C5]=0xA2362F, [0x3994CD]=0xAC342B,
      [0x399CCD]=0xAC342B, [0x411841]=0x351614, [0x41184A]=0x3D1614, [0x412041]=0x351C1A,
      [0x41204A]=0x3D1D1A, [0x412952]=0x432422, [0x413962]=0x50312F, [0x415A62]=0x503735,
      [0x415A6A]=0x573835, [0x41626A]=0x573835, [0x416273]=0x5E3835, [0x41627B]=0x653835,
      [0x416A6A]=0x573835, [0x416A83]=0x6B3935, [0x417383]=0x6B3935, [0x41738B]=0x723935,
      [0x417394]=0x793A35, [0x417B8B]=0x723935, [0x417B94]=0x793A35, [0x417B9C]=0x803A35,
      [0x41838B]=0x723935, [0x41839C]=0x803A35, [0x4183A4]=0x863B35, [0x4183AC]=0x8D3B35,
      [0x418BA4]=0x863B35, [0x418BAC]=0x8D3B35, [0x418BB4]=0x943C35, [0x418BBD]=0x9B3C35,
      [0x4194BD]=0x9B3C35, [0x4194C5]=0xA53A32, [0x419CC5]=0xA53A32, [0x419CCD]=0xAF372E,
      [0x419CD5]=0xBB3329, [0x41A4D5]=0xBB3329, [0x4A204A]=0x3D1D1A, [0x4A2052]=0x431D1A,
      [0x4A2952]=0x432422, [0x4A295A]=0x4A2422, [0x4A314A]=0x3D2A28, [0x4A3152]=0x432A28,
      [0x4A315A]=0x4A2A28, [0x4A3962]=0x50312F, [0x4A626A]=0x573E3D, [0x4A6273]=0x5E3F3D,
      [0x4A6A73]=0x5E3F3D, [0x4A7B9C]=0x80413D, [0x4A839C]=0x80413D, [0x4A83A4]=0x86423D,
      [0x4A83AC]=0x8D423D, [0x4A8BA4]=0x86423D, [0x4A8BAC]=0x8D423D, [0x4A8BB4]=0x94423D,
      [0x4A94AC]=0x8D423D, [0x4A94B4]=0x94423D, [0x4A94BD]=0x9E403A, [0x4A94C5]=0xA83E36,
      [0x4A9CBD]=0x9E403A, [0x4A9CC5]=0xA83E36, [0x4A9CCD]=0xB33A32, [0x4AA4CD]=0xB33A32,
      [0x4AA4D5]=0xBF362C, [0x4AA4DE]=0xCD3125, [0x4AACDE]=0xCD3125, [0x52205A]=0x4A1D1A,
      [0x52295A]=0x4A2422, [0x522962]=0x502522, [0x52315A]=0x4A2A28, [0x523952]=0x43302F,
      [0x52395A]=0x4A312F, [0x524162]=0x503735, [0x526273]=0x5E4543, [0x526A73]=0x5E4543,
      [0x527383]=0x6B4643, [0x52838B]=0x724643, [0x528394]=0x794743, [0x528B9C]=0x804743,
      [0x5294B4]=0x964741, [0x5294BD]=0xA1443D, [0x529CB4]=0x964741, [0x529CBD]=0xA1443D,
      [0x529CC5]=0xAB4139, [0x529CCD]=0xB73D35, [0x52A4C5]=0xAB4139, [0x52A4CD]=0xB73D35,
      [0x52A4D5]=0xC3392F, [0x52A4DE]=0xD13328, [0x52ACCD]=0xB73D35, [0x52ACD5]=0xC3392F,
      [0x52ACDE]=0xD13328, [0x52ACE6]=0xDF2E21, [0x52B4E6]=0xDF2E21, [0x5A295A]=0x4A2422,
      [0x5A2962]=0x502522, [0x5A296A]=0x572522, [0x5A315A]=0x4A2A28, [0x5A3162]=0x502B28,
      [0x5A316A]=0x572B28, [0x5A6294]=0x794D4A, [0x5A6A7B]=0x654C4A, [0x5A737B]=0x654C4A,
      [0x5A7383]=0x6B4C4A, [0x5A7B83]=0x6B4C4A, [0x5A838B]=0x724C4A, [0x5A839C]=0x804D4A,
      [0x5A8B94]=0x794D4A, [0x5A8B9C]=0x804D4A, [0x5AA4BD]=0xA34841, [0x5AA4C5]=0xAE453D,
      [0x5AA4CD]=0xBA4138, [0x5AA4D5]=0xC63C32, [0x5AACCD]=0xBA4138, [0x5AACD5]=0xC63C32,
      [0x5AACDE]=0xD5362B, [0x5AB4D5]=0xC63C32, [0x5AB4DE]=0xD5362B, [0x5AB4E6]=0xDE3428,
      [0x5AB4EE]=0xE83224, [0x5ABDE6]=0xDE3428, [0x5ABDEE]=0xE83224, [0x62296A]=0x572522,
      [0x62316A]=0x572B28, [0x623173]=0x5E2C28, [0x627B8B]=0x725350, [0x628B8B]=0x725350,
      [0x628B94]=0x795350, [0x628B9C]=0x805450, [0x6294A4]=0x88534F, [0x62A4C5]=0xB14941,
      [0x62ACC5]=0xB14941, [0x62B4DE]=0xD43D32, [0x62B4E6]=0xDE3B2F, [0x62B4EE]=0xE8382B,
      [0x62BDE6]=0xDE3B2F, [0x62BDEE]=0xE8382B, [0x62BDF6]=0xF33527, [0x62C5EE]=0xE8382B,
      [0x62C5F6]=0xF33527, [0x6A3173]=0x5E2C28, [0x6A396A]=0x57312F, [0x6A3973]=0x5E322F,
      [0x6A397B]=0x65322F, [0x6A4173]=0x5E3835, [0x6A417B]=0x653835, [0x6A4A73]=0x5E3F3D,
      [0x6A4A83]=0x6B403D, [0x6A5273]=0x5E4543, [0x6A8394]=0x795957, [0x6A9CA4]=0x895854,
      [0x6AB4D5]=0xC8463D, [0x6AB4DE]=0xD3443A, [0x6ABDDE]=0xD3443A, [0x6ABDE6]=0xDD4136,
      [0x6ABDEE]=0xE83F32, [0x6AC5EE]=0xE83F32, [0x6AC5F6]=0xF23B2E, [0x6AC5FF]=0xFF3729,
      [0x6ACDFF]=0xFF3729, [0x73397B]=0x65322F, [0x734183]=0x6B3935, [0x735273]=0x5E4543,
      [0x73527B]=0x654543, [0x73A4AC]=0x945C58, [0x73ACB4]=0x9E5954, [0x73ACBD]=0xA95650,
      [0x73ACC5]=0xB5524B, [0x73B4C5]=0xB5524B, [0x73B4CD]=0xBE5049, [0x73B4D5]=0xC74E46,
      [0x73BDDE]=0xD24C42, [0x73BDE6]=0xDD493E, [0x73C5E6]=0xDD493E, [0x73C5EE]=0xE7463A,
      [0x73C5F6]=0xF24236, [0x73CDEE]=0xE7463A, [0x73CDF6]=0xF24236, [0x73CDFF]=0xFF3E30,
      [0x73D5FF]=0xFF3E30, [0x7B4183]=0x6B3935, [0x7B418B]=0x723935, [0x7B5A83]=0x6B4C4A,
      [0x7B8BAC]=0x95615D, [0x7BA4B4]=0x9E5F5A, [0x7BA4BD]=0xAA5B56, [0x7BB4C5]=0xB35953,
      [0x7BB4CD]=0xBD5750, [0x7BBDCD]=0xBD5750, [0x7BBDD5]=0xC6554D, [0x7BBDDE]=0xD25249,
      [0x7BC5E6]=0xDC5046, [0x7BC5EE]=0xE74C41, [0x7BC5F6]=0xF2493D, [0x7BCDEE]=0xE74C41,
      [0x7BCDF6]=0xF2493D, [0x7BCDFF]=0xFF4437, [0x7BD5FF]=0xFF4437, [0x7BDEFF]=0xFF4437,
      [0x834A8B]=0x72403D, [0x834A94]=0x79413D, [0x83528B]=0x724643, [0x835A8B]=0x724C4A,
      [0x839CA4]=0x8C6966, [0x83ACBD]=0xA9625D, [0x83B4BD]=0xA9625D, [0x83CDE6]=0xDB564D,
      [0x83CDF6]=0xF14F44, [0x83D5F6]=0xF14F44, [0x83D5FF]=0xFF4A3E, [0x83DEFF]=0xFF4A3E,
      [0x8B5294]=0x794743, [0x8B529C]=0x804743, [0x8BACAC]=0x956D6A, [0x8BACBD]=0xA86A65,
      [0x8BBDBD]=0xA86A65, [0x8BC5D5]=0xC4635C, [0x8BCDE6]=0xDA5D54, [0x8BD5F6]=0xF1564B,
      [0x8BD5FF]=0xFF5144, [0x8BDEFF]=0xFF5144, [0x8BE6FF]=0xFF5144, [0x945A9C]=0x804D4A,
      [0x945AA4]=0x864E4A, [0x94BDBD]=0xA6726E, [0x94CDDE]=0xCE6861, [0x94D5F6]=0xF05D53,
      [0x94DEF6]=0xF05D53, [0x94DEFF]=0xFF574B, [0x94E6FF]=0xFF574B, [0x9C5AA4]=0x864E4A,
      [0x9CB4BD]=0xA47A77, [0x9CBDD5]=0xC1736D, [0x9CC5CD]=0xB77671, [0x9CD5E6]=0xD86C65,
      [0x9CE6FF]=0xFF5E52, [0xA462AC]=0x91514D, [0xA46AB4]=0x9C544F, [0xA4D5DE]=0xCC7771,
      [0xA4DEEE]=0xE36F67, [0xA4E6F6]=0xEF6A61, [0xA4E6FF]=0xFF6459, [0xAC6AB4]=0x9C544F,
      [0xAC8BB4]=0x9D6C68, [0xACDEE6]=0xD57B74, [0xACE6FF]=0xFF6A5F, [0xB483BD]=0xA9625D,
      [0xB483C5]=0xB2615B, [0xB48BC5]=0xB16863, [0xB4C5D5]=0xBC8A87, [0xB4D5D5]=0xBC8A87,
      [0xB4E6E6]=0xD4827D, [0xBD7BC5]=0xB35953, [0xBD83CD]=0xBC5F58, [0xBD9CBD]=0xA47A77,
      [0xBDD5D5]=0xB99391, [0xBDDEDE]=0xC5908C, [0xC5D5E6]=0xCF948F, [0xC5DEDE]=0xC39895,
      [0xCD94D5]=0xC36C65, [0xCDA4DE]=0xCC7771, [0xCDC5D5]=0xB69C9A, [0xCDDEE6]=0xCC9C99,
      [0xCDE6E6]=0xCC9C99, [0xD5B4DE]=0xC88682, [0xD5E6E6]=0xC8A5A3, [0xD5EEEE]=0xD79F9B,
      [0xDEE6EE]=0xD2AAA7, [0xDEEEEE]=0xD2AAA7, [0xDEF6F6]=0xE4A19C, [0xE6EEEE]=0xCCB5B4,
      [0xE6F6F6]=0xDFABA7, [0xEED5F6]=0xE79791, [0xEEE6EE]=0xCCB5B4, [0xF6E6F6]=0xDFABA7,
      [0xFFE6FF]=0xFF968F,
    },
  },
  [131] = {
    name = "lapras",
    hueRange = { min = -15, max = 5 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x398BCD,
    slide = { h = 56, l = 2, s = 0 },
  },
  [132] = {
    name = "ditto",
    hueRange = { min = -60, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xAC6294,
    slide = { h = -80, l = -2, s = 1 },
  },
  [133] = {
    name = "eevee",
    hueRange = { min = -30, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xBD7B4A,
    slide = { h = -140, l = 1, s = -5 },
  },
  [134] = {
    name = "vaporeon",
    hueRange = { min = -20, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x6ABDC5,
    slide = { h = 87, l = 0, s = 0 },
  },
  [135] = {
    name = "jolteon",
    hueRange = { min = -25, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFFF00,
    slide = { h = -20, l = -1, s = -5 },
  },
  [136] = {
    name = "flareon",
    hueRange = { min = -20, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xCD624A,
    slide = { h = -60, l = 0, s = -2 },
  },
  [137] = {
    name = "porygon",
    hueRange = { min = -40, max = 40 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xEEC5C5,
    slide = { h = -90, l = -3, s = 2 },
  },
  [138] = {
    name = "omanyte",
    hueRange = { min = -15, max = 60 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xDEBD83,
    slide = { h = -30, l = 1, s = -1 },
  },
  [139] = {
    name = "omastar",
    hueRange = { min = -15, max = 60 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xD5C583,
    slide = { h = -30, l = 1, s = -1 },
  },
  [140] = {
    name = "kabuto",
    hueRange = { min = -20, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xA46220,
    slide = { h = 40, l = 2, s = -7 },
  },
  [141] = {
    name = "kabutops",
    hueRange = { min = -40, max = 50 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x94735A,
    slide = { h = 50, l = 0, s = -5 },
  },
  [142] = {
    name = "aerodactyl",
    hueRange = { min = -60, max = 60 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xA49CB4,
    slide = { h = 50, l = -2, s = 2 },
  },
  [143] = {
    name = "snorlax",
    hueRange = { min = -10, max = 60 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xF6E6B4,
    slide = { h = 30, l = 1, s = -3 },
  },
  [144] = {
    name = "articuno",
    hueRange = { min = -20, max = 30 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x31A4D5,
    slide = { h = -40, l = 0, s = 1 },
  },
  [145] = {
    name = "zapdos",
    hueRange = { min = -20, max = 25 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFF9C39,
    slide = { h = -40, l = 2, s = 0 },
  },
  [146] = {
    name = "moltres",
    hueRange = { min = -20, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xFFD500,
    slide = { h = -80, l = 5, s = -3 },
  },
  [147] = {
    name = "dratini",
    hueRange = { min = -40, max = 20 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x94A4E6,
    slide = { h = 40, l = 0, s = 0 },
  },
  [148] = {
    name = "dragonair",
    hueRange = { min = -30, max = 10 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0x4183BD,
    slide = { h = 50, l = 2, s = -3 },
  },
  [149] = {
    name = "dragonite",
    hueRange = { min = -20, max = 25 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xE6AC5A,
    slide = { h = 130, l = 0, s = -4 },
  },
  [150] = {
    name = "mewtwo",
    hueRange = { min = -70, max = 90 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xBDBDDE,
    slide = { h = -40, l = -1, s = -2 },
  },
  [151] = {
    name = "mew",
    hueRange = { min = -40, max = 60 },
    -- the colour this species is mostly MADE of, and what its shiny
    -- shift does to it. A flat sprite cannot be recoloured, only
    -- multiplied, and the multiply has to be measured against the
    -- body colour: averaged over a balanced set of references a
    -- hue rotation cancels itself out to no tint at all.
    dom = 0xEEDEEE,
    slide = { h = -80, l = 0, s = 0 },
  },
}
