-- tools/save_variants_check: old and wrapped saves through the real import
-- path (SaveFileIO -> SaveVariants -> codecs), in its OWN identity.
function love.conf(t)
  t.identity = "Gen2Recomp_savevariantscheck"
  t.window = false
  t.modules.audio = false
  t.modules.sound = false
end
