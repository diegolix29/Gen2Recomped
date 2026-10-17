# Pokéwalker art (Higgsfield)

The Pokéwalker app uses painted art when it finds it in `assets/pokewalker/`. Any file that's missing falls back to the code-drawn version, so the files can arrive one at a time. The Pokémon themselves always come from the imported games' own sprites, never from generated art.

**Course backgrounds:** `course_<theme>.png`
- 16:9, ideally 1920×1080.
- Horizontally seamless: the right edge has to continue into the left edge, because the scene scrolls as the Pokémon walks.
- Nothing in the lower middle third, where the Pokémon walks.
- No characters, no creatures, no text, no logos.

**Tile icons:** `icon_<tile>.png`
- Square, 512×512, on a transparent or flat dark background.

## Shared style (prepend to every prompt)

> Clean modern 2D game background art, soft painterly shading, bright friendly
> colours, gentle depth with three parallax layers (far, middle, near), flat
> open ground strip across the bottom quarter, wide 16:9 side-scrolling
> composition, horizontally seamless and tileable, no characters, no animals,
> no creatures, no people, no text, no logos, no UI

## Course backgrounds

| File | Courses | Prompt (after the shared style) |
| --- | --- | --- |
| `course_field.png` | Refreshing Field, Hoenn Field, Sinnoh Field, Amity Meadow | rolling green meadow with wildflowers, soft blue sky with puffy clouds, distant low hills, morning light |
| `course_forest.png` | Noisy Forest, Big Forest, Treehouse, Yellow Forest | deep pine and broadleaf forest, sun rays through the canopy, mossy ground path, ferns at the edges |
| `course_road.png` | Rugged Road, Winner's Path | dirt road through rocky grassland, scattered boulders, distant mountains, clear afternoon sky |
| `course_beach.png` | Beautiful Beach, Warm Beach, Stormy Beach, Resort, Beyond the Sea | sandy tropical beach, turquoise sea and gentle waves, palm trees, bright sun |
| `course_lake.png` | Blue Lake, White Lake | calm blue lake with reeds and lily pads, grassy shore, distant forested hills, reflections |
| `course_cave.png` | Dim Cave, Scary Cave, Quiet Cave | dim cave interior, glowing blue crystals in the rock walls, rocky floor, soft ambient light |
| `course_volcano.png` | Volcano Path | volcanic mountain path, dark rock, distant smoking volcano, warm orange sky, faint lava glow |
| `course_snow.png` | Icy Mountain Rd | snowy mountain road, snow-covered pines, icy peaks, pale winter sky |
| `course_night.png` | Night Sky's Edge | grassy hilltop at night, starry sky with a large moon, soft blue night light |
| `course_town.png` | Suburban Area, Town Outskirts, Sightseeing, Rally | quiet small town outskirts, colourful houses with red roofs, a paved path, trees, sunny day |

## Tile icons

For these, replace "background" in the shared style with "a single glossy app icon, centred, rounded, soft shadow, transparent background":

| File | Prompt |
| --- | --- |
| `icon_walk.png` | two footprints walking |
| `icon_radar.png` | a radar dish sending out signal waves |
| `icon_dowse.png` | a dowsing rod with a glowing tip |
| `icon_bag.png` | an adventurer's satchel bag |
| `icon_card.png` | an ID card with a star |
| `icon_settings.png` | a gear |

## Model and credits

The account is on the free plan with 10 credits. A cheap image model such as Nano Banana or Z Image covers the ten backgrounds first. Generate in Higgsfield's web app. This session's Higgsfield connection can list generations but cannot start them, so the generated images get pulled in from the account's history once they exist.

## What is installed (2026-10-17)

The images in `assets/pokewalker/` were generated in Higgsfield (Z Image) from the prompts above, then prepared with the scratch scripts (PIL):

**Backgrounds:** `course_<theme>.jpg`, ten files.
- Most generations came out as three stacked strips (the prompt's "three parallax layers" was taken literally). Each file is the top strip, sky plus the first ground band, which fits the app's wide course banner.
- Each is resized so its height is at most 540 and its width at most 4096, to stay inside mobile GPU texture limits. JPEG quality 88, about 70–220 KB each.
- Seamlessness comes from the app, not the file: it draws image, mirrored image, image… as the course scrolls.
- One generation was unused (an empty sky over a thin strip), and so was a portrait-shaped field variant.

**Icons:** `icon_<tile>.png`, six files.
- The generations had grey gradient backgrounds and soft shadows. These were cut out by flood-filling from the edges along the gradient, at 256 px.
- The alpha was eroded by one pixel and feathered (Gaussian 1.1), then each icon was trimmed to its contents.

**Next time:** for single-scene backgrounds, drop "three parallax layers" from the shared style and ask for "one continuous scene". For icons, ask for "isolated on pure white" or "on solid #00FF00" so the cut-out is exact.
