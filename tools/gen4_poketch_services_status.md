# Platinum Pokétch and counter repair

The Platinum cache marker changed: opening the ROM rebuilds its graphics cache.
Pokétch backgrounds now use the archive's generic LCD palette, the border's
tile offset and palette bank, and the map apps' actual tile sheet. The LCD is
192 by 160 pixels and clips app art before drawing the shell. Color Changer
remaps the ROM LCD palettes; a LOVE rendering check verifies the shader.

Touch controls cover bezel navigation, calculator, drawing, calendar marks,
counter, coin toss, stopwatch, timer, alarm, markers, roulette, Move Tester,
and the color slider.
Desktop mouse callbacks now route to interactive screens without requiring
POKEPORT_TOUCH. Window scale and letterboxing are removed before bottom-screen
hit testing; injected native-panel coordinates bypass that transform. Camera
look no longer steals mouse drags while an interactive screen is open.
Calculator, timer, alarm, stopwatch and Move Tester text use aligned display
positions. Move Tester has the six ROM arrow hit areas, memo has touch erase/
clear controls, and party/history/friendship icon clicks play Pokémon cries.

Matchup Checker selects two non-egg party members and
checks breeding compatibility. Pokémon History retains twelve acquisition
snapshots from successful captures, gifts, and hatches. Stopwatch and Kitchen
Timer advance on the real game clock even while the watch is closed. The party,
friendship and daycare apps read save state. These three apps now render the
imported Pokémon icons, with text fallbacks for missing assets. Party HP bars
and all six icons fit inside the LCD; icon textures use nearest filtering.
Fresh-ROM rendering exposed and corrected party HP-bar placement and the daycare
layout: party overlays now sit inside the background's six bars, and daycare
uses the two horizontal spaces above the fence art.
These are functional port implementations; sprite placement, animations and
interaction details are not yet complete cartridge parity.
Coin Toss now resolves heads, tails and spin cells through the ROM's NANR
sequences, animates with the original rise/acceleration/bounce constants, rests
at (112,144), and ignores repeated tosses while airborne. Sound remains absent.

The mart uses its extracted Platinum background and DS windows, supports
buying and selling numeric item IDs, and retains the script's return callback.
Touch input follows the presented UI scale and supports selecting rows, paging,
quantity adjustment, purchase confirmation and back navigation. Berry-name
script buffering now preserves the command's slot/item argument order.
All twenty specialty stock lists are read from the ROM's ARM9 pointer table,
including town second clerks and the department store's items, TMs and berries.
The nurse's shared message bank is preserved, and its healing-animation command
waits for the animation before resuming the script. Healing balls use the ROM's
3D map models relative to the console, rather than Game Boy healing sprites.

Berry Searcher now reads ROM growth parameters, initial bushes, map positions,
and static map sprite cells. Persistent growth supports watering, mulch, harvest,
and replant expiry; full bags preserve ripe fruit. Existing berry scripts can
open the appropriate bag pocket. Bushes are activated when their map is loaded;
exact visibility activation and watering animations remain. The field renderer
now switches patches between the extracted sprout, growing, blooming and fruit
sheets, and suppresses bush art for empty or newly planted soil without hiding
the interactive object. Stage sparkle and moisture effects remain unimplemented.
Dowsing and hidden-item scripts now share the ROM's collected-item flags.
Scans use the actual tap position, native tile-to-LCD positions and each item's
8/24/48-pixel ROM detection range. Faint signals do not reveal exact markers;
button activation scans the player center. The scan pulse remains a port overlay.

Remaining work: Trainer Counter needs
Poké Radar chains; Link Searcher needs wireless support. Seal, decoration and
Frontier shops need their separate inventory and currency systems.
Marking Map tracks active roaming Pokémon using all 29 route positions extracted
from the ROM, follows route changes and excludes retired roamers. Roamers use
the ROM map sprite. Six persistent map markers can be selected and dragged,
using their ROM small/enlarged cells and updated drawing priority. Legacy dot
marks remain visible; initial marker placement is the port's bottom-row layout.
Map sprites currently show static sequence cells; affine animation and the
player cursor/hidden-location overlays remain unfinished.
Nurse TV animation and exact sound timing need visual QA.
The existing imported dataset passed texture, geometry, prop and console checks
across 31 service interiors. Sandgem's mart and center were rendered and visually
inspected in LOVE. These static previews exclude NPCs and do not prove the full
interactive entry, nurse and clerk flows; those still need in-game playtesting.
A ROM traversal visits 152 instructions reachable from the nurse's shared entry:
normal service instructions have handlers; contest contestant-name buffering
reached by the broader common-script graph remains unsupported.

Checks: run the services and ROM checks through `tools/run_lua_check.py`, plus
the existing bottom-screen, panel and branch checks. The runner uses the local
Windows LOVE LuaJIT DLL. Run `love tools/gen4_lcd_shader_check` from the repository
root for the graphics check; it writes its result beside the check source.
The interior check accepts the imported dataset root as its argument. The LOVE
service-render check accepts the dataset root and an output directory and writes
mart/center PNG previews there.
The Poketch render check accepts the same dataset/output arguments and composes
all app previews from freshly decoded ROM backgrounds/cell sprites plus imported
icons and the actual Platinum font.

Additional gameplay repairs:
- Outdoor survey zoom uses the shared matrix bounds; a 1536x1024 Sandgem render
  was inspected and includes neighboring routes, trees and the shoreline.
- The importer now preserves blocked terrain behavior separately, including
  counters and ledges. The ROM check found 344 counter cells in 32 service rooms.
- Ledge interaction reads the imported Platinum direction table.
- Battle bag use closes the screen immediately and ignores repeated selections.
- Encounters include Platinum's 40/70-percent movement roll and rate-dependent
  grace period, reset on map entry and after battles. Special-date modifiers
  remain unimplemented.
- Route 202's catching command launches a demonstration with a separate party,
  bag and dex and resumes the field script on completion. It currently reuses
  the shared automatic throw flow; Platinum's exact weakening turn, tutorial
  timing and explanatory battle messages are not yet reproduced.
- Pokédex lists now read ROM Sinnoh/National orders and the list background.
  Habitat, size, forms, search and DS scroll-wheel parity remain unfinished.
- Party backgrounds use the correct menu tile sheet; names, icons and HP use
  native window positions. HP reads stats.hp and eggs hide level/HP overlays.
  Party and Pokédex list selection accept scaled mouse/touch input.

`gen4_gameplay_regression_check.lua` accepts the dataset root; the dex render
check accepts output directory followed by dataset root. These checks do not
replace an interactive playthrough of every service and tutorial path.

## Title, naming and indoor viewport follow-up

- Platinum finite-map views preserve the display aspect ratio when capped to map bounds. Presentation expands the capped view to fill the window, so zooming out stops at available room space without introducing an additional black frame. Cartridge-authored empty areas inside the room remain part of the map.
- Title screens use independent full 256x192 logo/top and Giratina/bottom panels for the display and inset modes. Off/swap uses Giratina behind the logo, without the copyright strip. The title owns its second screen instead of falling through to the Poketch.
- Giratina's imported BTA0 texture scroll now reaches Gen4TexAnim and Gen4Model; idle lighting no longer stays at intro-dark brightness. Older opaque copyright imports have their black background discarded in the title compositor.
- Gen4NamingScreen consumes supplied presets before the keyboard. Player naming offers the gender-appropriate Lucas/Dawn default when no player presets are supplied; rival naming uses the imported rival list. New Name opens the keyboard. Controller, mouse and touch choices are supported, including scaled keyboard taps.
- Validation: 36 Platinum viewport assertions, 37 older-generation bounded-view checks, title rendering plus ROM scroll/input checks, 142 Poketch/services checks, 66 bottom-screen checks and 34 gameplay regression checks passed.
- Limits: this does not establish complete title-intro cutscene parity or full native lighting parity. Player Lucas/Dawn defaults are a port convenience when the cache has no recommended player-name list. Live gameplay on the user's device remains unverified.

## Audio, Pokédex, PC and field-feature follow-up

- Native SDAT SSEQ playback now uses ROM SBNK instruments and SWAR PCM/ADPCM samples through a LOVE queueable Source. Map day/night music, battle/victory themes, bicycle, Surf, title, evolution and numeric script effects resolve from the ROM catalogue. Numeric species cries now resolve the name-keyed imported WAVs. Script sound/cry waits poll playback, and StopSE stops numeric effect sources.
- Validation: nine sampled music/effect sequences produce nonzero PCM; 1,010 native sequence programs execute for 600 ticks without unsupported commands; native title music sustains playback through LOVE's actual audio device. This is not an auditory comparison of every song. DS envelope, vibrato, tie/portamento and PSG fidelity remain incomplete.
- Pokédex exposes Info, Area, Cry, Size and Forms pages with mouse/touch/controller navigation. All 493 footprints are imported from pokefoot.narc. Area searches read species fields and enabled encounter methods rather than matching levels/rates. Alternate form images use the imported named records. Area, cry and size tile sheets now use native loader pairings. Search, time-conditioned map highlighting, live cry waveform/dials, full size comparison, seen-form tracking and native dual-screen page composition remain incomplete.
- PC storage uses 18 boxes of 30 slots, the native box background and 32 wallpaper resources. Deposit, withdraw, cross-box moves/swaps, cancellation, summary, naming, wallpaper changes, marking, held-item transfer and confirmed release are wired. Sparse slots remain stable and removing the last usable party member is refused. Native party-panel art, multi-selection, compare/search, secret-wallpaper unlocks, mail and exact HM-release restrictions remain incomplete.
- Single-screen title logo is half-size and top-center. Boot copyright appears before the studio card. Native portal and face models now precede Giratina, with corrected fade-step counts and the final hold. The separate GameOpening montage, exact opening camera/lighting and timing remain incomplete.
- Gen4EvolutionState replaces the Game Boy fallback with the ROM evolution background and Platinum-sized sprite surface. Evolution application, cancellation, cries and move learning use shared transactions. Silhouette timing is reconstructed; native particles, clamp transitions and full animation parity remain incomplete.
- Native numeric field-move IDs and Platinum badge-list positions now drive overworld eligibility. Party actions include Dig, Teleport and Sweet Scent; Sweet Scent bypasses walking encounter grace/rate checks. Full HM object interactions, all native field animations and weather restrictions still require work.
- Honey Trees lower all four native commands, use the ROM's three encounter tables, persist 21 map locations, six-hour readiness and 24-hour expiry, choose trainer-dependent Munchlax trees, preserve native repeat-slather/group/slot/shake rolls and consume Honey when battling. Pressing A from below the native tree prop compiles the original common script. Native shaking animation, RTC tamper handling and live field-play verification remain incomplete.
- Cache revision is platinum-audio-ui-v11. Restart and reopen Platinum to refresh an older cache. Changes remain local and uncommitted.

### October 1 follow-up: logo, storage, shop, Switch audio and Giratina

- Half-size title logo uses four-sample alpha-aware downsampling and removes bright pixels touching transparency before filtering. Native dual-screen logo is preserved.
- Giratina now retains per-vertex matrix restores through the packed model and renderer. All 26 native joint slots round-trip, and the tentacles are visible in the LOVE title capture. Exact title lighting remains incomplete.
- Storage grid uses native icon centers (112+24*column, 40+24*row), wallpaper placement (88,0), centered box name and extracted ROM hand cursor, with synchronized touch targets. Held-item names appear in the preview. Party-panel, cursor animation, multi-selection and advanced features remain incomplete.
- Shop now shows the selected item's ROM icon and description. Item names and right-aligned prices share a baseline without overlap; transaction messages override descriptions until the selection moves.
- Switch audio fixes propagate the active cache prefix to synthesis workers, separate bank caches by prefix, and redirect native audio/SoundData decoders through the same version shim as images. Mono file effects become 16-bit stereo. Seven Switch filesystem checks and seven worker-recovery checks pass. Real desktop LOVE music/effect/cry playback passes; physical Switch output remains unverified.
- Fresh ROM render verification loads 543 supplementary UI assets. Storage/field checks (22), shop/Poketch checks (142), cursor/joint checks and diff whitespace checks pass.
