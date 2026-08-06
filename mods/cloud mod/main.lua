return function(mod)
mod.content.sprites:patch("SPRITE_RED", {
  image = mod.assets:path("assets/sonicplayer.png"),})
mod.content.sprites:patch("SPRITE_RED_BIKE", {
  image = mod.assets:path("assets/sonicplayer_bike.png"),
})
end