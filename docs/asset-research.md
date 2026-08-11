# Asset Research — Elevator Game Prototype

Research for a 2D mobile-first Godot game: cutout side view of a building, passengers with
destination floors, player-designed elevators. Style target: Mini Motorways / Mini Metro —
flat, minimal, readable on small phone screens. Date: 2026-08-11.

---

## Recommended Starting Kit (TL;DR)

**Approach: programmer-art-first, with a small set of drop-in packs.** The Mini Motorways
aesthetic *is* flat geometry — rounded rectangles, solid fills, 2–3 accent colors. You will get
closer to the target look with `ColorRect`/`Panel`/`Polygon2D` + a Godot theme than with any
generic asset pack, and the whole game state (shafts, cars, floors, queues) stays data-driven
and re-themeable per level (office / hospital / spaceship = palette + icon swap).

Drop these in on day one:

| Need | Pick | License | Link |
|---|---|---|---|
| Passenger bodies | **Kenney Shape Characters** (100 assets, mix-and-match geometric parts — perfect for sumo=wide, businessman=tall silhouettes) | CC0 | https://kenney.nl/assets/shape-characters |
| Passenger mood (impatience) | **Kenney Emotes Pack** (480 emotes, vector + pixel styles) | CC0 | https://kenney.nl/assets/emotes-pack |
| UI chrome | **Kenney UI Pack** (430 assets, flat panels/buttons/sliders) | CC0 | https://kenney.nl/assets/ui-pack |
| UI font | **Inter** (numbers/HUD) or **Rubik** (friendlier, rounded — closer to Mini Motorways vibe) | SIL OFL | https://fonts.google.com/specimen/Rubik |
| Themed icons (bed, briefcase, rocket…) | **game-icons.net** (4,100+ monochrome SVGs, easy to recolor) | CC-BY 3.0 (credit authors) | https://game-icons.net/ |
| UI sounds | **Kenney Interface Sounds** (100) + **Kenney UI Audio** (50) | CC0 | https://kenney.nl/assets/interface-sounds · https://kenney.nl/assets/ui-audio |
| Elevator ding | Pixabay "elevator ding" search (Pixabay Content License — free, no attribution) | Pixabay | https://pixabay.com/sound-effects/search/elevator-ding/ |
| Footsteps | **Kenney RPG Audio** (has footstep00–09 among 50 sfx) | CC0 | https://kenney.nl/assets/rpg-audio |

Everything above except game-icons.net is CC0 — zero attribution bookkeeping during the
prototype. Keep a `CREDITS.md` from day one anyway (game-icons.net authors go there).

---

## 1. Art Approach Recommendation (prototype phase)

**Do programmer art for the building, use packs only for characters, emotes, icons, audio.**

Reasons:

- **The target style is vector-flat.** Mini Metro/Motorways ships what is essentially styled
  debug-draw: solid-color rounded rects, circles, and lines. Godot gives you this for free via
  `ColorRect`, `Panel` + `StyleBoxFlat` (corner radius, borders, shadows — all code-driven),
  `Polygon2D`, and `draw_*()` calls. No pixel-art pack will look *more* like the target.
- **Everything must scale/re-theme.** Elevator shafts of arbitrary height, buildings of
  arbitrary width, 3 planned themes. Procedural rects re-theme with a palette swap;
  sprite packs don't.
- **Readability at phone size** comes from silhouette + color contrast, which you control
  precisely with shapes. Test rule: a passenger should read at ~24–32 px tall.
- **Characters are the one thing worth importing.** Distinct passenger silhouettes (sumo,
  businessman, patient on gurney, astronaut) are slow to draw well. Kenney **Shape Characters**
  is modular geometric bodies (separate parts, SVG sources) that match a flat style; recolor
  per passenger type and scale width/height for weight classes. If it feels too "platformer",
  fall back to pure programmer art: capsule + head circle, vary width/height/color — that is
  literally what Mini Motorways-like crowds are.

Concrete starter recipe in Godot:

1. Building = `PanelContainer`/`ColorRect` stack; floors = horizontal `HBoxContainer` rows or a
   custom `_draw()` grid. Shaft = tall rounded rect; car = smaller rounded rect tweened on Y.
2. Passengers = `Node2D` with a capsule `Polygon2D` (or Shape Characters sprite), colored by
   destination floor (Mini Metro trick: shape/color = destination).
3. One `Theme` resource with `StyleBoxFlat` everywhere; per-level palettes as dictionaries
   (office: grays + one accent; hospital: white/teal/red cross; spaceship: dark + neon).
4. Emote bubble (Kenney Emotes) above impatient passengers; ding on arrival.

---

## 2. 2D Asset Packs

### Kenney (kenney.nl) — all CC0, first stop for everything

- **Shape Characters** — 100 assets, modular geometric characters, SVG sources included.
  https://kenney.nl/assets/shape-characters (also on OpenGameArt and itch.io)
- **Toon Characters 1** — 270 assets, more detailed cartoon people (businessman-ish types);
  heavier style, use only if Shape Characters feels too abstract.
  https://kenney.nl/assets/toon-characters-1
- **UI Pack** — 430 flat UI assets (buttons, panels, sliders). https://kenney.nl/assets/ui-pack
- **Emotes Pack** — 480 emotes in vector + pixel + balloon styles.
  https://kenney.nl/assets/emotes-pack
- **Game Icons** + **Game Icons Expansion** — simple flat white icons, good for HUD.
  https://kenney.nl/assets/game-icons · https://kenney.nl/assets/game-icons-expansion
- Full 2D catalog: https://kenney.nl/assets/category:2D/ — also browsable pre-packaged for
  Godot in the Godot Asset Library (e.g. "Kenney UI Audio",
  https://godotengine.org/asset-library/asset/796).

### itch.io

Direct "building cutout with elevator" packs basically don't exist; closest hunting grounds:

- Free minimalist 2D packs: https://itch.io/game-assets/free/tag-2d/tag-minimalist
- Interior packs (mostly pixel-art, useful for themed props, not the core look):
  https://itch.io/game-assets/free/tag-2d/tag-interior
- Hospital-tagged assets: https://itch.io/game-assets/tag-hospital
- Free 2D spaceship/sci-fi: https://itch.io/game-assets/free/tag-2d/tag-spaceship and
  https://itch.io/game-assets/free/tag-2d/tag-science-fiction (e.g. "Space Station Ada")
- **MiniFolks – Humans** (LYASeeK) — tiny readable people sprites, pixel style:
  https://lyaseek.itch.io/minifhumans (check page for license; itch licenses vary per pack —
  always read the pack page)
- Kenney's packs mirrored: https://kenney-assets.itch.io/

Caveat: most itch interior/people packs are pixel art, which fights the flat-vector target.
Use them only if you pivot the art direction to pixel.

### OpenGameArt.org

- Kenney's full CC0 catalog is mirrored: https://opengameart.org/content/all-cc0-uploader-kenney
- Shape Characters mirror: https://opengameart.org/content/shape-characters
- Searchable by license (filter CC0). Little that's specifically "elevator/building cutout";
  treat it as a fallback for one-off props and sounds.

### CraftPix (craftpix.net)

- Freebies section: https://craftpix.net/freebies/ ; full catalog:
  https://craftpix.net/all-game-assets/
- Style is detailed/cartoon or pixel — generally *not* a match for the minimal target, but
  they have themed interior/tileset packs (office, hospital-adjacent) if you want richer
  backdrops later. License: CraftPix's own royalty-free license (commercial use OK, no
  resale/redistribution of raw assets); freebies same terms. Paid packs typically $5–20.

### Godot Asset Library / Godot-specific

- **ThemeGen** — generate Godot themes from GDScript code, great fit for the
  programmer-art approach: https://godotengine.org/asset-library/asset/3299
- Godot UI theme browser (community themes, live preview):
  https://forum.godotengine.org/t/godot-ui-theme-browser/73981
- Kenney UI Audio packaged for Godot: https://godotengine.org/asset-library/asset/796
  (also https://github.com/Calinou/kenney-interface-sounds)

---

## 3. Fonts (all SIL Open Font License via Google Fonts — free, commercial OK, embeddable)

- **Inter** — the default screen-UI choice; excellent small-size legibility, tabular figures
  (good for floor numbers/timers). https://fonts.google.com/specimen/Inter
- **Rubik** — slightly rounded sans, friendly without being childish; closest to the
  Mini Motorways feel. 5 weights + italics. https://fonts.google.com/specimen/Rubik
- **Nunito / Nunito Sans** — rounded geometric, warmer option, 7 weights.
  https://fonts.google.com/specimen/Nunito
- **M PLUS Rounded 1c** — very round, good if you want a softer/cuter tone.
  https://fonts.google.com/specimen/M+PLUS+Rounded+1c
- Suggestion: **Rubik Medium/Bold for headings & floor numbers, Inter for body/HUD.** Two
  families max. Godot 4 imports variable-font TTFs directly.

## 4. Icon Sets

- **game-icons.net** — 4,100+ game-oriented SVG icons (briefcase, bed, syringe, rocket,
  sumo-ish figures, weight, up/down arrows), monochrome so trivially recolored to your
  palette. License CC-BY 3.0 — credit authors ("Icons made by {author}, game-icons.net").
  https://game-icons.net/ (FAQ/license: https://game-icons.net/faq.html)
- **Kenney Game Icons (+ Expansion)** — CC0, simpler/flatter, smaller selection. Links above.
- **Lucide** — clean 1.5px-stroke general UI icons (settings, pause, close), ISC license
  (attribution not required). https://lucide.dev/
- **Material Symbols** — Google's icon set, Apache 2.0, huge coverage incl. elevator/stairs
  icons. https://fonts.google.com/icons

## 5. Audio

### SFX packs (prototype-ready, CC0 unless noted)

- **Kenney Interface Sounds** — 100 clicks/confirms/snaps. https://kenney.nl/assets/interface-sounds
- **Kenney UI Audio** — 50 button/switch sounds. https://kenney.nl/assets/ui-audio
- **Kenney Digital Audio** — beeps/blips, good for spaceship theme. https://kenney.nl/assets/digital-audio
- **Kenney Impact Sounds** — thuds; pitch down for the sumo landing. https://kenney.nl/assets/impact-sounds
- **Kenney RPG Audio** — includes footstep00–09, cloth, creaks (door open/close!).
  https://kenney.nl/assets/rpg-audio
- Kenney full audio category: https://kenney.nl/assets/category:Audio

### Elevator dings / chimes / ambience

- **Pixabay SFX** — many "elevator ding"/"elevator chime" clips; Pixabay Content License
  (free, commercial OK, no attribution required):
  https://pixabay.com/sound-effects/search/elevator-ding/ ·
  https://pixabay.com/sound-effects/search/elevator%20chime/
- **Mixkit** — 60+ bell sounds, Mixkit License (free, commercial OK):
  https://mixkit.co/free-sound-effects/bell/
- **freesound.org** — search "elevator ding" and filter license = CC0 (many results are
  CC-BY — check per-file). Good for hospital PA ambience and office room tone too.
- freesoundslibrary.com elevator ding is CC-BY 4.0 (attribution required) — prefer the
  Pixabay/CC0 options to skip bookkeeping.

Prototype sound plan: one ding (arrival), one click (UI), one whoosh (car moving, loop),
footstep tick (boarding), emote pop (impatience escalation). All coverable by
Kenney packs + one Pixabay ding.

---

## 6. License Cheat Sheet

| License | Attribution? | Commercial? | Sources here |
|---|---|---|---|
| CC0 | No | Yes | All Kenney packs, filtered OpenGameArt, some freesound |
| CC-BY 3.0/4.0 | **Yes** | Yes | game-icons.net, much of freesound/OpenGameArt |
| SIL OFL | No (keep license file) | Yes | Inter, Rubik, Nunito, M PLUS |
| ISC / Apache 2.0 | No (keep notice) | Yes | Lucide / Material Symbols |
| Pixabay / Mixkit content licenses | No | Yes | Pixabay SFX, Mixkit SFX |
| CraftPix license | No | Yes (no asset resale) | CraftPix freebies + paid |
| itch.io per-pack | Varies | Varies | Read each pack page |

Action item: add `CREDITS.md` to the repo now; log every imported asset + license as you go.
