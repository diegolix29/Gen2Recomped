-- Simple test mod - just try to load and log
return function(mod)
  mod.log:info("Simple test mod loaded successfully!")
  mod.log:info("Mod ID: %s", mod.id)
  mod.log:info("Mod assets path: %s", mod.assets and mod.assets:path("") or "no assets")
end