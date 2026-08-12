# Art Asset Options — 2D *and* 3D, re-examined

Broad art-direction research for the v3 "Path Drawing" prototype (Godot 4.2, portrait
720x1280, mobile-first). This deliberately goes **wider** than `docs/asset-research.md`
(2026-08-11), which was 2D-only and landed on "Kenney + programmer art". That earlier
recommendation is re-tested here against the 3D and pre-rendered options, not repeated.

Date: 2026-08-12. Nothing here has been bought or imported; this is a decision document.

---

## 0. Recommendation up front

**Stay with code-drawn primitives as the rendering strategy, and spend the art budget on a
*design pass* (palette, type, spacing, motion, iconography) rather than on asset packs.**
Buy exactly two cheap things as insurance: a CC0 mega-pack for one-off props/icons/SFX, and
a good font pair. Do not go 3D.

That is not a "don't buy stuff" reflex — it falls out of three findings:

1. **Almost every load-bearing pixel in this game is dynamic and generated.** Read
   `scripts/v3/grid.gd:214-320`: the route polylines (nudged per-route so overlaps stay
   readable), the hazard borders that *open at edges shared with the same gate group* so a
   corridor reads as one tunnel, the occupied-corridor tint in the holding car's colour, the
   loop chevrons, the live drag preview, the retiring-route ghost line, the redeploy ghost +
   countdown, the pulsing gate-wait outline. **No asset pack in any store ships these.** They
   are the game's visual language, and they are already code.
2. **The art budget per entity is tiny.** `passenger3.gd:71-97` draws a passenger as a
   **10 px-radius circle** (20 px across) carrying a 12 px destination letter, a 26x4 patience
   bar, and sometimes a "?" bubble — inside a 90 px cell. At 20 px there is no silhouette to
   read. Character packs (Kenney Shape Characters, MiniFolks, Synty rigs) are all
   over-specified for a token that small; you would be paying for detail that gets destroyed
   at import scale. The type distinction that *does* work at 20 px is exactly what's already
   there: hue + ring + a 2-rect briefcase tick.
3. **The closest shipped comparable made this same call, out loud.** Matthew Viglione of
   SomaSim on *Project Highrise* (a 2D cutaway tower sim, ~100 floors): *"3D art can get
   really expensive and it would limit the variety we could build. Also, we think that it
   will be a lot easier to manage a tower in a cutaway view than having to constantly change
   floors."* (SomaSim community group,
   <https://groups.google.com/g/project-highrise-by-somasim-games/c/iynTP4iU4Lo>). Their art is
   described as taking SimTower's pixels and *vectorising* them — i.e. flat shapes, not models.

### Ranked paths

| # | Path | What you actually do | Rough effort | Cost |
|---|---|---|---|---|
| **1** | **Stylised primitives + design pass** (recommended) | Extract a `Palette` resource + per-theme dicts; one Godot `Theme` for the code-built HUD; replace `ThemeDB.fallback_font` with Rubik/Inter; SDF rounded-rect + drop-shadow shaders on cells and cars; a motion pass (door easing, boarding hops, impatience shake, gate-denied nudge); icon set for the 3 passenger types + cards | **3–6 focused days** for a night-and-day improvement; ~2 more days for per-theme palettes | **~$0** (+ $19.95 optional) |
| **2** | **Primitives + a bought flat-vector icon/UI layer** | Path 1, plus RhosGFX SVG icon/UI packs (or Kenney All-in-1) for card chips, HUD glyphs, room-function badges, win/lose overlays. Godot rasterises SVG at import scale, so author at 2x | Path 1 **+ 1–2 days** integration | **$20–$60** |
| **3** | **Pixel-art repaint (only if you want a different game's mood)** | Adopt a 16px grid, e.g. Netherzapdos *Pixel Spaces* (has elevators/doors/stairs and a hospital expansion) or LimeZu *Modern Interiors* for props, and repaint cells/cars as sprites. Requires abandoning immediate-mode `_draw` for a TileMap/Sprite2D architecture and re-authoring every dynamic overlay as a sprite or shader | **2–4 weeks**, and it changes the genre feel | **$1.50–$15** in assets, most of the cost is your time |

**Rejected: full 3D ortho "dollhouse"** (§3) and **pre-rendered 2.5D** (§4). Short version of why,
because the 3D case is stronger than expected and deserves a fair summary:

- The *assets* for 3D are genuinely better than for 2D — Kenney/Quaternius/KayKit ship CC0 GLB
  modular interiors and 161 free rigged humanoid animations, and Synty's EULA explicitly is
  *"not limited by game engine"*, so Godot use is legal. This is not an availability problem.
- It fails on **engine**: Godot 4.2 has a confirmed, unfixed-until-4.3 orthographic-camera
  shadow bug ([#78422](https://github.com/godotengine/godot/issues/78422)), MSAA black-screen
  bugs on Android Mobile ([#81910](https://github.com/godotengine/godot/issues/81910)), and
  FBX-only vendors need the external FBX2glTF binary (`ufbx` landed in 4.3).
- It fails on **screen size**: with shadows off you lose the lighting that makes low-poly read,
  and Godot's own mobile docs warn specifically against dense geometry concentrated in a small
  part of the screen — a literal description of 20–40 px passengers clustered in a 630×900 box.
- It fails on **theming**: nobody — Kenney, Quaternius, KayKit or Synty — ships a hospital kit.
  One of your three planned themes has no supply.

Audio is the one place with a real, cheap gap worth closing now: **Bfxr2/jsfxr** for the UI
tones and the **CC0 Tallbeard/Abstraction loop bundle** for music (§7).

### The one thing that would change this answer

If the design pivots from *diagram* to *scene* — visible furnished rooms, passengers with
readable bodies and props, tenants doing things — then the token scale grows past ~48 px and
character/interior packs start earning their price. That is a different game than the one in
`README.md`, and it is worth being explicit that it is a design choice, not an art choice.

---

## 1. What this game's art actually has to do

Derived from the code, not from vibes:

| Element | Current implementation | On-screen size | Can a pack supply it? |
|---|---|---|---|
| Grid cell (`.`, `#`, `R`, `G`) | `draw_rect` + hatch/border (`grid.gd:249`) | 90x90 px | Partly (a tileset), but only if drawing moves to a TileMap |
| Gate corridor | Hazard stripes computed per shared edge + live occupancy tint | 90 px, group-aware | **No** — geometry depends on runtime flood-fill |
| Route polyline | `draw_polyline` with per-route nudge, chevrons on loops | 4 px stroke | **No** |
| Drag preview | Live, per-frame, follows the finger | — | **No** |
| Car | Rect body + two sliding door leaves + capacity pips + `!` badge + ghost/countdown states | ~60 px | Marginally (a sprite sheet), but the door phase is data-driven |
| Passenger | 20 px circle, dest letter, patience bar, exec ring + briefcase | **20 px** | **No** — too small for character art |
| HUD | Built entirely in code (`hud3.gd`, no `.tscn` UI) | — | **Yes** — a `Theme` resource drops straight in |

Two structural notes that constrain any asset decision:

- `Grid3._process` calls `queue_redraw()` **every frame** (`grid.gd:210`). The whole board is
  immediate-mode. Moving to sprites/tilemaps is not "swap a texture", it is an architecture
  change to the file that also owns the maze data.
- The HUD being 100% code-built is *good news* for buying UI: a Godot `Theme` resource applies
  to code-instantiated `Control`s with one `theme = preload(...)` line. This is the cheapest
  real upgrade available.

---

## 2. Beyond Kenney — the 2D landscape

### 2.1 Does a "cutaway building" pack exist? (verifying the earlier claim)

**Verdict: the earlier research was right, and I'd state it more strongly.** Searching itch.io
by `interior`, `interiors`, `office`, `house`, `building`, `skyscraper`, `city-builder`, and
explicit "cross-section"/"cutaway" terms returns three clusters, none of which is a
cutaway-building kit:

- **Top-down RPG interiors** — the dominant category. Best-in-class is **LimeZu, *Modern
  Interiors*** (<https://limezu.itch.io/moderninteriors>): name-your-price from $1.50, 16/32/48 px
  variants, thousands of props, a character generator with 100+ outfits, *and it explicitly
  covers office, waiting room, reception, hospital and morgue themes*. Excellent pack, wrong
  projection (top-down RPG).
- **Isometric room kits** — e.g. **Isometric Interiors** by pixel_Salvaje ($18,
  <https://itch.io/game-assets/tag-interior/tag-tileset>). Wrong projection again.
- **Platformer side-scroller tiles** — side view, but authored for a character walking on
  floors with sky behind, not a sealed cross-section grid.

The nearest genuine hits, and they are small:

| Pack | Creator | Price | License | Notes |
|---|---|---|---|---|
| [Pixel Spaces — 2D Room/City Building Full Pack](https://netherzapdos.itch.io/pixel-spaces) | Netherzapdos | PWYW, **$15 for commercial** | Commercial OK on paid tier; no resale, **no AI training**; free tier is non-commercial only | 1454 assets, 16x16 base (32x32 chars), PNG. Has walls/floors/**doors/elevator/stairs**, 30 animated NPCs, UI, and free expansions incl. **hospital** + police + cafe. Explicitly Unity/Godot. The single closest thing to a cutaway building kit that exists. |
| [Animated Elevator Doors (16px grid)](https://pixel-assembly.itch.io/animated-elevator) | Pixel Assembly | free/cheap | per-page | 32x48 animated elevator with door cycle. Tiny but on-the-nose. |
| [2D Sidescroller Office Tileset](https://itch.io/game-assets/tag-office) | rixitic | **$1** | per-page | 16x16, explicitly "office building interiors", side view |
| [Skyscrapers Building Assets](https://alb-pixel-store.itch.io/skycrapers-building-assets) | ALB Pixel Store | paid | per-page | Tower Bloxx-style exteriors, not interiors |

All of these are **pixel art**. There is no flat-vector cutaway kit. This is not a gap in the
search; it is a gap in the market, and it makes sense: cutaway tower sims are a handful of
games (SimTower, Yoot Tower, Tiny Tower, Project Highrise, Mad Games Tycoon), each of which
authored bespoke art tied to its own grid metrics.

### 2.2 Creators worth naming (and what they're actually good for)

| Creator | Style | Fit for this game | Link / license |
|---|---|---|---|
| **RhosGFX** | Clean **flat vector**, SVG sources | **Best non-Kenney fit.** Icons, UI, furniture, avatars, structures. SVG means you recolour to your palette and export at any size — the one property that matters for per-theme reskins. | <https://rhosgfx.itch.io/> — Vector Icon Pack $19.99 / PRO SVG $29.99; Cartoony UI Pack $9.99; Vector Structures $4.99 / PRO $6.99; Vector Furniture $7.99; Vector Avatars $6.99. Licence: use in unlimited commercial projects, **no resale, and client/commission work needs the $89.99 Commercial Licence** |
| **Kenney** | Flat vector + pixel, CC0 | Still the baseline. Note the **All-in-1 bundle: $19.95, 60,000+ assets, CC0, PNG/SVG/OBJ/FBX/GLTF/OGG, free lifetime updates** — <https://kenney.itch.io/kenney-game-assets>. Recent additions include *Isometric Vector Buildings/Roads* and a *Sketch Town Expansion*. As cheap insurance this is unbeatable. | CC0 |
| **LimeZu** | 16/32/48 px modern interiors | Superb, top-down only. Has office + hospital. | <https://limezu.itch.io/moderninteriors> — PWYW $1.50+, **credit required**, no redistribution |
| **Netherzapdos** | 16 px rooms/buildings | See above — closest to cutaway | PWYW $15 commercial |
| **Penzilla** | Pixel tilesets, GUI, icons | Prolific and cheap, but fantasy/farming/cyberpunk themed; nothing modern-building | <https://penzilla.itch.io/> |
| **Cainos** | 32 px fantasy platformer/top-down | Widely used with Godot, license is generous (commercial OK, modify OK, credit optional, no resale) — but the content is fantasy villages. **No fit.** | <https://cainos.itch.io/> |
| **Pixel Frog** | 16 px platformer (Pixel Adventure, Treasure Hunters) | CC0 and lovely, but platformer-shaped. **No fit.** | <https://pixelfrog-assets.itch.io/> |
| **Anokolisa** | 16 px top-down / sidescroller fantasy | **No fit.** | <https://anokolisa.itch.io/> |
| **Screaming Brain Studios** | Textures, tiny texture packs, fonts — **all CC0** | Useful for background textures/fonts if you ever want surface noise | <https://screamingbrainstudios.com/downloads/> |
| **CraftPix** | Detailed cartoon / pixel | Themed interiors exist but the style is far richer than the target; royalty-free own licence, commercial OK, no resale. Freebies at <https://craftpix.net/freebies/> | $5–20 typical |
| **GameDeveloperStudio** (Robert Brooks) | Glossy cartoon vector characters | Very permissive licence (<https://www.gamedeveloperstudio.com/license.php>: no royalties, no tiered/maximum use), $3.95–$15.95 packs, supporter freebies. Style is bubbly/glossy — fights the minimal target. | per-asset |
| **KatGrabowska / Leonid Deburger / Norwade** | Flat icon sets ($1.99–$9.99) | Cheap flat icon top-ups if RhosGFX misses something | itch.io `tag-flat` |
| **Open Peeps / Humaaans** (Pablo Stanley) | Hand-drawn & flat-geometric **CC0** vector people | Not for in-game (too big), but **free, CC0, commercial-OK** and genuinely good for store page, tutorial screens, marketing | <https://www.openpeeps.com/> · <https://www.humaaans.com/> |
| **Shapeforms** | Audio (see §7) | Complete Collection $149 direct, bundles ~$47–50 on itch; explicitly OK in Godot | <https://shapeforms.com/> |

### 2.3 Marketplace crossovers — the licensing answer is better than expected

Both big engine stores now permit non-native-engine use, which was worth checking:

- **Unity Asset Store**: *"You can use Unity Asset Store assets with other engines, as long as
  you comply with the Unity Asset Store EULA."* — official support article,
  <https://support.unity.com/hc/en-us/articles/34387186019988>. Restrictions: no redistribution
  as standalone/extractable assets, no cost-sharing on a purchase, no monetising asset-derived
  UGC, and some assets carry extra "Restricted Asset Terms".
- **Fab (Epic)**: the Standard License says assets may be used *"with any compatible tools"* —
  not limited to Unreal (<https://www.fab.com/eula>). Practical catch: much of the catalogue
  ships in UE-specific formats, so you may be re-exporting to `.glb`/`.obj` yourself.
- **Synty** advertises Unity, Unreal **and Godot** directly on their own store
  (<https://syntystore.com/>).
- **Humble** runs frequent gamedev asset bundles, increasingly labelled Unity+Unreal+Godot.

So "it's a Unity pack" is no longer a blocker. Format and style remain the real blockers.

### 2.4 Godot-side 2D notes

- **SVG import rasterises at import time** at a configurable scale (a 32x32 SVG at 2x imports
  as 64x64). For a fixed 720x1280 portrait viewport with `canvas_items` stretch this is fine —
  author at 2x and forget it. If you ever need runtime re-rasterisation there is a
  Godot 4.2 plugin (<https://godotengine.org/asset-library/asset/2164>) and
  <https://github.com/Giwayume/godot-svg>, but you do not need them.
- **Free game `Theme` resources**: *Themey* (<https://github.com/wadlo/Themey>) — `.tres` +
  images, graphics CC0, code MIT, Godot 4.x; and the index at
  <https://github.com/maxfieldev/godot-themes-hub>. ⚠️ *Godot Minimal Theme*
  (passivestar) is an **editor** theme, not a game UI theme — commonly mistaken.
- **Shaders for the "stylised primitives" path**: SDF rounded rect + outline + shadow
  (<https://godotshaders.com/shader/frosted-glass-shader-rounded-rect-outline-shadow/>),
  free effects pack (<https://hollow-pixel.itch.io/godot-4-essential-2d-effects-free-shader-pack>),
  2D drop shadow (<https://godotshaders.com/shader/2d-drop-shadow/>). This is how primitives stop
  looking like primitives.

---

## 3. The 3D option, taken seriously

The premise: model the building in low-poly 3D, view it through an **orthographic** camera as a
dollhouse cutaway (Sims build view / Two Point Hospital), keep the same grid logic underneath.

### 3.1 The assets genuinely exist and are mostly free

This is the surprise: the 3D supply is *better* than the 2D supply for this game's subject
matter. Modular interior kits are a mature category; cutaway 2D tilesets are not.

| Source | License | Formats | Relevant packs | Price |
|---|---|---|---|---|
| **Kenney 3D** | **CC0** | **OBJ, FBX, GLB** (Kenney's own docs recommend GLB for Godot) | [Furniture Kit](https://kenney.nl/assets/furniture-kit) (140), [Building Kit](https://kenney.nl/assets/building-kit) (80), [Modular Buildings](https://kenney.nl/assets/modular-buildings) (~100), [City Kit Commercial](https://kenney.nl/assets/city-kit-commercial) (50, exteriors), [Space Station Kit](https://kenney.nl/assets/space-station-kit) (90, tagged *interior*), [Modular Space Kit](https://kenney.nl/assets/modular-space-kit), [Mini Characters](https://kenney.nl/assets/mini-characters) (25, animated, incl. wheelchair users), [Blocky Characters](https://kenney.nl/assets/blocky-characters) | Free |
| **Quaternius** | **CC0** ([FAQ](https://quaternius.com/faq.html)) | .blend / FBX / OBJ, GLB on newer packs (**inconsistent per pack** — the Ultimate Modular Women page contradicts itself) | [Ultimate Modular Sci-Fi](https://quaternius.com/packs/ultimatemodularscifi.html) (46 modular sci-fi interior models), [Ultimate House Interior](https://quaternius.com/packs/ultimatehomeinterior.html) (120+), Ultimate Furniture, [Universal Animation Library 2](https://quaternius.com/packs/universalanimationlibrary2.html) (**130+ anims, FBX+GLB, universal humanoid rig explicitly stated compatible with Godot**) | Free |
| **KayKit** (Kay Lousberg) | **CC0** | **OBJ, FBX, GLTF** | [Character Animations](https://kaylousberg.itch.io/kaykit-character-animations) (**161 humanoid animations incl. idle/walk/wave/sit** — free, GLTF), [City Builder Bits](https://kaylousberg.itch.io/city-builder-bits), [Space Base Bits](https://kaylousberg.itch.io/space-base-bits), [Furniture Bits](https://kaylousberg.itch.io/furniture-bits) | Free / $3.95 "Extra" / $5.95 source; **Complete KayKit $150** |
| **Synty POLYGON** | One-time purchase; **[EULA is explicitly not engine-limited](https://syntystore.com/pages/one-time-purchase-licence)** — *"The licence is worldwide, and is not limited by game engine"*; 5 seats per purchase | FBX/OBJ source + Unity/Unreal projects; **22 packs now ship a native Godot project** ([list](https://syntystore.com/collections/godot-asset-packs)) | **[POLYGON Office Pack $49.99](https://syntystore.com/products/polygon-office-pack)** — 772 assets, 626 props, **128 modular building pieces incl. a modular stairwell and modular ceiling/roof**, 18 office characters. **[Sci-Fi Space $149.99](https://syntystore.com/products/polygon-sci-fi-space-pack)**, [Sci-Fi City $49.99](https://syntystore.com/products/polygon-sci-fi-city) (has a Godot project), [City Pack $19.99](https://syntystore.com/products/polygon-city-pack) (Godot project) | $19.99–$349.99; SyntyPass $30–40/mo |
| **Poly Pizza** | **Mixed CC0 / CC-BY per model** — check each | **GLB + FBX**, no login | 10,600+ models; hosts GLB bundles of Quaternius packs — the fastest way to get Quaternius content as GLB | Free |
| **ITHappy Studios** | ⚠️ unverified (site 403s) | GLTF/FBX/OBJ/Blender | [Hospital Interior Rooms](https://ithappystudios.com/interiors/hospital-interior-rooms/), [Hospital Floors](https://ithappystudios.com/interiors/hospital-floors/), [Sci-Fi Rooms](https://ithappystudios.com/interiors/sci-fi-rooms/) (608 assets). Also on Fab. **The only purpose-built low-poly hospital interior kit found anywhere.** | unverified |
| **Poly Haven** | CC0 | — | **Not suitable** — photoreal PBR scans, opposite art direction | Free |

Notes: Kenney's character assets were made by Kay Lousberg, so **Kenney + KayKit + Quaternius
visually match**, all use tiny gradient atlases (KayKit's 1024² atlas is stated as
downsampleable to **128×128**), and all batch to very few materials. That's the ideal property
for mobile.

**The theming gap mirrors 2D exactly: nobody has a hospital kit.** Kenney, Quaternius, KayKit
and Synty all lack one (Synty's nearest is [POLYGON Horror Asylum, $99.99](https://syntystore.com/products/polygon-horror-asylum) — doctors, nurses,
patients, surgery rooms, but horror-toned). Since hospital is one of your three planned themes,
this is a real cost, not a footnote.

### 3.2 Godot 4.2 viability — this is where 3D loses

Format and licensing are fine. The engine specifics are not.

- **Orthographic + shadows is broken in 4.2.** [godotengine/godot#78422](https://github.com/godotengine/godot/issues/78422) — *"Shadows broken with orthogonal camera in 3d both in editor and in game"* — is confirmed, opened against 4.0.2, milestoned for **4.3** (PR #92287). **4.2 is inside the affected window.** Also [#120457](https://github.com/godotengine/godot/issues/120457) (incorrect directional shadow-map culling with ortho cameras — some objects get no shadow at all), plus community reports of striped artifacts and a light beam at certain Y levels. Workaround is `shadow_pancake_size` tuning and a very tight far plane — or just turning shadows off.
- **MSAA on the Mobile renderer can black-screen on Android.** [#81910](https://github.com/godotengine/godot/issues/81910): with MSAA enabled and **no transparent objects in the scene**, the resolve subpass is skipped. [#84783](https://github.com/godotengine/godot/issues/84783): 2D MSAA breaks silently when there is no 2D element drawn. A 3D-only cutaway scene hits both.
- **FBX on 4.2 needs an external binary.** Godot 4.2 imports FBX via **FBX2glTF**, which links the proprietary FBX SDK; the built-in `ufbx` importer only landed in **4.3**. Synty ships FBX source, and there is a known texture-binding bug ([#97600](https://github.com/godotengine/godot/issues/97600) — Synty FBXs reference `.psd`/Dropbox paths rather than the shipped PNGs). Community converters exist ([synty-godot-converter](https://github.com/DeniedWorks/synty-godot-converter) — **targets 4.6**, [synty-in-godot](https://github.com/tctimmeh/synty-in-godot), [FBX Batch Importer](https://godotengine.org/asset-library/asset/4017)). Synty's own Godot projects target **4.5.1+** and will not open in 4.2. **Verdict: ship GLB only** — which points at Kenney/KayKit/Quaternius, not Synty.
- **Mobile renderer feature losses** ([docs](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html)): no VoxelGI/SDFGI/SSIL/SSR/SSAO, no volumetric fog, no DoF, **no debanding**, no TAA/FSR2/SMAA, no decals, no RenderingDevice access, and lower colour precision. Most don't matter here; **no debanding does** — gradient atlases plus a flat background band visibly on mobile panels.
- **Depth buffer is sometimes 16-bit on mobile** ([3D rendering limitations](https://docs.godotengine.org/en/4.2/tutorials/3d/3d_rendering_limitations.html)). An ortho camera framing a whole 10-storey tower has a wide near/far spread → Z-fighting risk between coplanar wall/floor pieces.
- **Transparency sorts per-node-origin, not per-vertex.** Any "ghost the front wall so you can see inside" cutaway effect — the defining trick of the genre — lands squarely in Godot's weakest sorting path. Recommended fix is alpha-scissor, i.e. no smooth fade.
- **Draw-call budget.** Practical mobile guidance converges on **~100–200 draw calls** ([slicker.me field guide](https://slicker.me/godot/mobile-optimization.html) says ~100 for 60 fps; [others](https://gtstu.com/godot-4-optimize-android-ios/) say under 200 safe, 200–500 borderline, 500+ thermal-throttles budget chips). Mobile drivers cost **2–5× more CPU per draw call than desktop**. Reachable — a 7×10 grid of modular pieces is textbook [MultiMeshInstance3D](https://docs.godotengine.org/en/4.2/tutorials/performance/using_multimesh.html) or GridMap territory, and MultiMesh's no-frustum-culling drawback is a non-issue with a fixed camera. So this one is **solvable**, not fatal.
- **The killer, from Godot's own 3D performance docs:** *"Do not worry about vertex count so much on mobile, but avoid concentration of vertices in small parts of the screen... small objects with a lot of geometry within a small portion of the screen forces mobile GPUs to put a lot of strain on a single screen cell."* That is a literal description of this game — dozens of characters at 20–40 px, clustered in a 630×900 region of a 720×1280 screen.

### 3.3 Does Synty-style art even *read* at phone size in ortho?

Honest answer: **partly, and not in the way you need.** Synty/Kenney low-poly reads well
because of *form under lighting* — bevels, chunky silhouettes, baked-in colour blocking. At
20–40 px, in ortho, with shadows disabled (which §3.2 forces), you lose the lighting that
carries the form and you are left with flat coloured blobs — i.e. you have paid a full 3D
pipeline to arrive at worse-looking flat shapes than `Polygon2D` gives you for free.

Two Point Hospital and The Sims read at that fidelity because they are played at **desk
distance on a large screen with a zoomable perspective camera**, and their characters occupy
far more pixels than yours ever will. That is a different readability regime.

---

## 4. The hybrid — pre-rendering 3D to 2D sprite sheets

### 4.1 The tooling is healthy

| Tool | Link | Price | License | Notes |
|---|---|---|---|---|
| **Sprite Sheet Maker** (ManasMakde) | [Blender Extensions](https://extensions.blender.org/add-ons/sprite-sheet-maker/) · [GitHub](https://github.com/ManasMakde/SpriteSheetMaker) | Free | MIT | Most actively maintained (updated Nov 2025). Built-in pixelation, auto camera framing, 6 preset axes + custom orbit, ortho or perspective |
| **Sprite Sheet Generator** (GameSomeStudio) | [Blender Extensions](https://extensions.blender.org/add-ons/sprite-sheet-generator/) · [GitHub](https://github.com/GameSomeStudio/sprite-sheet-generator) | Free | GPL-3.0+ | Blender 4.2 LTS+. **Rotates the armature, not the camera**, so lighting stays fixed across directions. Batch-processes all actions |
| **Spritesheet Renderer** (chrishayesmu) | [GitHub](https://github.com/chrishayesmu/Blender-Spritesheet-Renderer) | Free | OSS | Most "production" feature set: material passes (bake normal/AO/roughness sheets), JSON metadata |
| **blender-spritesheets** (theloneplant) | [GitHub](https://github.com/theloneplant/blender-spritesheets) | Free | MIT | Old (Blender 2.81) but ships **Unity and Godot importers** + a JSON sidecar — useful as a metadata-format reference |
| **TexturePacker** | [product](https://www.codeandweb.com/texturepacker) · [Godot plugin](https://github.com/CodeAndWeb/texturepacker-godot-plugin) | **$49.99** perpetual, 1 yr updates | commercial (plugin MIT) | `godot-spritesheet` exporter writes a `.tpsheet`; the plugin turns it into an `AnimationLibrary` for `AnimationPlayer` + `Sprite2D` |
| **Free Texture Packer** | [GitHub](https://github.com/odrick/free-tex-packer) | Free | **MIT** | Native `godot` export target + CLI. ⚠️ the project's own domain now redirects to a parked page and the author states only critical bugs get fixed — use the GitHub source |
| **Godot native** | [2D Sprite Animation docs](https://docs.godotengine.org/en/stable/tutorials/2d/2d_sprite_animation.html) | Free | MIT | `SpriteFrames` has an **"Add frames from a Sprite Sheet"** grid slicer built in. For a single-angle game you may need no external packer at all |
| **Godot SpriteFrames Atlas Trimmer** | [GitHub](https://github.com/jamiethorpe/Godot-SpriteFrames-Atlas-Trimmer) | Free | OSS | Trims blank space — a direct VRAM win, since transparent pixels cost the same as opaque at fixed bits-per-pixel |

Also: [godot-aseprite-wizard](https://github.com/viniciusgerevini/godot-aseprite-wizard) and
[Importality](https://godotengine.org/asset-library/asset/2025) if you ever hand-draw instead.

### 4.2 What it costs, from teams who actually did it

- **Factorio** ([FFF #172](https://factorio.com/blog/post/fff-172), [FFF #218](https://www.factorio.com/blog/post/fff-218), [FFF #227](https://factorio.com/blog/post/fff-227)): Blender → masks → After Effects compositing → Python post-processing. They consolidated 21 `.blend` files into one file with 21 scenes with linked meshes, and wrote custom Python to auto-generate render layers and compositor nodes. **A full animation set is 40+ hours on one PC**, so they distribute renders across machines. 4,000+ sprites, **~2.4 GB VRAM for sprites alone** at hi-res, split across logical atlases. Going hi-res also *changed the models*, because shaders and detail behave differently at scale.
- **Dead Cells** ([Game Developer deep dive](https://www.gamedeveloper.com/production/art-design-deep-dive-using-a-3d-pipeline-for-2d-animation-in-i-dead-cells-i-)): 3ds Max → FBX → custom "pixelizer". Stated payoffs are **cheap retakes** (no redrawing every frame) and **rig/animation reuse across characters** — "hundreds of hours" saved. Note both payoffs assume *many characters with many animations*.
- ⚠️ **Graveyard Keeper is a myth in this context.** Lazy Bear's [public writeup](https://www.gamedeveloper.com/programming/graveyard-keeper-how-the-graphics-effects-are-made) is about **runtime Unity shaders** — sprites layered in 3D space so Unity lighting applies, LUT colour grading, dynamic torch lights, **normal maps on 2D sprites** — not pre-rendering. Don't cite it as a prerender case study.

### 4.3 Why it is the wrong tool *here*

1. **The pipeline's value proposition is N viewing angles.** This game has a **single fixed
   orthographic view**. You'd need 1 angle. The entire multi-angle machinery — the reason
   these addons exist — is dead weight.
2. **Pre-render buys lighting, volume and material detail.** A flat-vector target has none of
   those to buy. You'd be rendering solid-colour shapes to PNG.
3. **It destroys iteration speed.** Today a colour tweak is a hot-reload. In this pipeline it
   is re-render (minutes–hours) → repack atlas → reimport → look. For a game still balancing
   its *readability*, that trade is backwards.
4. **Atlas memory:** a 2048² RGBA32 atlas is ~16 MB raw; ASTC 4×4 / ETC2 cuts it ~75%. Not
   fatal, but it's memory you currently spend zero of.

**The one place it would pay off:** if you ever want 20+ distinct passenger silhouettes with
idle fidgets, rendering one rigged tiny person and sheeting the variants beats hand-tuning 20
polygon rigs. Park the idea; don't build the pipeline speculatively.

---

## 5. Style-fit judgement, approach by approach

### A. Flat vector / stylised primitives (current + design pass)
- **Reads at phone size?** Best of the four. Silhouette and hue are the only channels that
  survive at 20 px, and this approach is *made* of silhouette and hue. Route lines, gate
  stripes and car colours are already the clearest thing on screen.
- **Calm minimal systems game?** Yes — this *is* the Mini Metro/Motorways idiom, and it's what
  Project Highrise chose for the same reasons.
- **Production time:** lowest. Days, not weeks. No import step, no atlas, no pipeline.
- **Per-level theming (office / hospital / spaceship):** cheapest possible — a palette
  dictionary and a handful of icons per theme. `levels3.gd` is already a data table; a
  `theme:` key slots straight in. **This is the single strongest argument.** Sprite and model
  kits re-theme by *re-authoring assets*; primitives re-theme by editing a dict.
- **Risk:** looks unfinished if you *don't* do the design pass. Programmer art and stylised
  primitives are separated by typography, spacing, easing and palette discipline — real work,
  just not asset-purchase work.

### B. Pixel art 2D
- **Reads at phone size?** Yes at 16–32 px *if* you commit to an integer-scaled pixel grid.
  Your 90 px cells and 20 px tokens don't align to a pixel grid today; you'd re-derive metrics.
- **Calm minimal?** It reads *cozy/retro*, not *calm/clinical*. That's a genre signal, and it
  moves you toward Tiny Tower rather than Mini Metro.
- **Production time:** weeks. `grid.gd`'s immediate-mode `_draw` would become a TileMap +
  sprites, and every dynamic overlay (gate stripes computed from flood-fill, route nudging,
  drag preview, occupancy tint, chevrons) must be re-implemented as sprites or shaders anyway.
- **Per-level theming:** moderate — Pixel Spaces has a hospital expansion; office and spaceship
  would come from different packs and would need style-matching (hand work).
- **Best supply:** [Pixel Spaces](https://netherzapdos.itch.io/pixel-spaces) ($15 commercial) is genuinely close to a cutaway kit.

### C. Low-poly 3D orthographic ("dollhouse")
- **Reads at phone size?** Weakest. Ortho + shadows-off (which Godot 4.2 forces, §3.2) removes
  the lighting that gives low-poly its form. Fine geometry clustered in a small screen region
  is explicitly warned against in Godot's own mobile docs.
- **Calm minimal?** It's a *different* aesthetic — charming, toy-like, busier. Perfectly
  legitimate; just not the stated target.
- **Production time:** highest. Even with free CC0 kits, budget weeks: scene assembly, camera
  and depth tuning, MultiMesh batching, a whole new visual language for routes and gates (which
  are 2D overlays and would sit in a `CanvasLayer` anyway — so you end up maintaining *both*
  pipelines), plus real-device testing against three known 4.2 bug classes.
- **Per-level theming:** most expensive. Three themes = three modular kits, style-matched.
  Spaceship is well served (Kenney Space Station Kit, Quaternius Ultimate Modular Sci-Fi);
  office is served but only well by paid Synty; **hospital is served by essentially nobody.**
- **Verdict: no.** Not because the assets are bad — they're better than the 2D supply — but
  because the engine version, the screen size and the theming budget all point the other way.

### D. Pre-rendered 2.5D
- Inherits 3D's authoring cost *and* 2D's runtime, while adding a slow re-render loop. Its one
  advantage (many angles from one model) is irrelevant to a fixed ortho view.
- **Verdict: no**, with the narrow exception noted in §4.3.

### The legibility test that decides it

A player must instantly parse, on a ~5" screen: **which line is which car's route**, **where
each car is**, **which corridor is locked and by whom**, **who is about to expire**. Every one
of those is a *diagram* problem — line weight, hue separation, contrast, motion. None of them
is a *scene* problem. Approaches C and D spend their budget on scene quality and then have to
overlay a diagram on top anyway.

---

## 6. Animation and motion

Recommendation: **code-driven `AnimationPlayer` + `Tween` on primitives.** Concretely:

| Motion | Technique | Why |
|---|---|---|
| **Door open / exchange / close** | `AnimationPlayer`, one authored track per phase, driving the two leaf rects' X | It's a fixed, repeatable, multi-property sequence: slide leaves, tick a light, fire SFX, call `_on_doors_open()`. Godot's docs literally use a door as the canonical `AnimationPlayer` example. Already partly implemented (`car3.gd:605-616`) — this is a polish pass, not a rewrite |
| **Car movement** | Keep the existing polyline stepping; add easing on start/stop and a subtle squash on arrival | The car already interpolates along `route.cells`. `Path2D` + `PathFollow2D` is the idiomatic alternative (set `rotates = false`, `loop = false` for an upright car) but would fight the direction-aware loop logic in `car3.gd`. **Don't refactor to Path2D** — the win is easing, not plumbing |
| **Passenger boarding** | `Tween` chains on `Node2D` (walk-in → pause → absorb), with staggered per-passenger delays via `Tween.parallel()` / `chain()` | Runtime-parameterised (variable distance, variable count) — Tween's home turf. Staggering is what makes a crowd read as a crowd |
| **Impatience tells** | Looping `AnimationPlayer` tracks on `modulate` / `scale` / `rotation`, `speed_scale` scaled by urgency; plus a pulse shader | State-driven loops you want to author and preview. Currently it's just a bar draining — a jitter + hue shift + a *sound* at the 25% mark is far more legible at 20 px than any sprite could be |
| **Gate denied / queued** | Already a pulsing outline (`car3.gd:632`) — add a small recoil nudge toward the gate | Communicates "blocked by another car", not "broken" |
| **Redeploy countdown** | Already a ghost + countdown — add a sweep ring | Reinforces that the delay is a cost |

**Ownership rule** (the one real Godot gotcha): decide per property whether code, `Tween`, or
`AnimationPlayer` owns it. If several write the same property in one frame the result depends
on update order. Also note `AnimationPlayer` property writes land on the *next* frame.

What to **rule out**:

- **`Skeleton2D`/`Bone2D` cutout rigging** — [docs](https://docs.godotengine.org/en/stable/tutorials/animation/2d_skeletons.html) still carry a "work in progress" banner, and naive polygons deform badly due to auto-triangulation (fix requires hand-placed internal vertices). Massive overkill for a 20 px circle.
- **Rive** — no official Godot runtime. The best unofficial one ([RiveGD](https://github.com/maidopi-usagi/RiveGD)) **requires Godot 4.5+**, its README says *"DO NOT USE IN PRODUCTION"*, it's untested on Android/iOS, and the OpenGL backend is broken. Rule out.
- **DragonBones** — the Godot 4.2+ runtime ([Daylily-Zeleen/Godot-DragonBones](https://github.com/Daylily-Zeleen/Godot-DragonBones), MIT) is alive and maintained, but the **editor has been abandoned since 2020** (last release 5.6.3; dragonbones.com is dead). Don't build a pipeline on it.
- **Spine** — genuinely works ([official spine-godot](https://en.esotericsoftware.com/spine-godot), GDExtension or engine-module flavours; the GDExtension has no `AnimationPlayer` integration and no C# bindings). But **Essential is $69 (no meshes) / Professional $379**, and there's a hard revenue gate pushing you to Enterprise above $500k. For sliding two rectangles, absurd.
- **Live2D `gd_cubism`** — for Godot 4.1/4.2 you must pin `v0.8.2-godot4.1`. Wrong tool anyway (expressive character faces).

---

## 7. Audio

The earlier doc covered Kenney adequately. Worth adding:

| Source | License | Price | Note |
|---|---|---|---|
| **Sonniss #GameAudioGDC** — [gdc.sonniss.com](https://gdc.sonniss.com/) · [all years](https://sonniss.com/gameaudiogdc/) · [license](https://sonniss.com/gdc-bundle-license/) | Custom royalty-free, worldwide, **no attribution**, unlimited projects, lifetime. Prohibited: reselling the SFX as-is, **training AI on them**, claiming authorship | **Free** | **The biggest single win here.** ~200 GB across years; the 2026 bundle is 7.47 GB. ⚠️ **there was no GDC 2025 bundle.** Professional field-recording quality; downside is giant 96 kHz WAVs you must audition and cut |
| **Bfxr2** ([repo](https://github.com/increpare/bfxr2), [bfxr.net](https://www.bfxr.net/)) / **[jsfxr](https://sfxr.me/)** / **[jfxr](https://github.com/ttencate/jfxr)** | Full rights to generated sounds, commercial or otherwise; Bfxr itself Apache 2.0 | Free | **The right primary source for this game.** A minimal systems game's audio identity is short abstract UI tones — ding, door thunk, impatience buzz, gate-denied blip, level-complete arpeggio. Generate them in seconds with zero licence surface. (Bfxr2 replaced the Flash version in Mar 2025 and is still BETA) |
| **Tallbeard / Abstraction — [Free Music Loop Bundle](https://tallbeard.itch.io/music-loop-bundle)** and **[Three Red Hearts](https://tallbeard.itch.io/three-red-hearts-prepare-to-dev)** | **CC0** (author *requests*, doesn't forbid, no NFT/AI use) | Free (NYOP) | Highest-value music download available: 200+ game-structured loops, no credit line, no risk |
| **[Shapeforms Audio Free SFX](https://shapeforms.itch.io/shapeforms-audio-free-sfx)** · **ObsydianX Interface SFX Pack 1 (CC0)** · **[Kronbits 200 Free SFX](https://kronbits.itch.io/freesfx)** | per-pack, CC0 where marked | Free | ObsydianX is UI clicks/beeps — directly your HUD. Shapeforms' paid [Complete Collection is $149](https://www.shapeforms.com/shop/p/complete-collection-2024) (bundles ~$47–50 on itch) and is explicitly Godot-OK |
| **Freesound** ([CC0 browse](https://freesound.org/browse/tags/cc0/)) | Mixed CC0 / CC BY / **CC BY-NC** | Free | ⚠️ **Use the licence facet or the "Free Cultural Works" filter.** CC BY-NC is commercially unusable — the #1 licensing mistake indies make here |
| **OpenGameArt** ([100 CC0 SFX](https://opengameart.org/content/100-cc0-sfx), [CC0 Sound Effects](https://opengameart.org/content/cc0-sound-effects)) | Free licences only (site rejects NC/ND); still per-asset | Free | ⚠️ its auto-generated credits file is explicitly not guaranteed accurate |
| **[Pixabay](https://pixabay.com/service/license-summary/)** / **[Mixkit](https://mixkit.co/license/)** | Royalty-free, commercial OK, no attribution required | Free | Pixabay bans standalone resale and trademark-containing content; you clear third-party IP yourself |
| **[ZapSplat](https://www.zapsplat.com/license-type/standard-license/)** | Free tier **requires crediting "ZapSplat"**; Gold removes it, and Gold-era downloads stay attribution-free for life | Free / Gold ~£39.99/yr ⚠️ price unverified | Only worth it if you need breadth fast |
| **[Kevin MacLeod](https://incompetech.com)** (CC BY 4.0) / **[Juhani Junkala](https://www.free-stock-music.com/artist.juhani-junkala.html)** (CC BY 3.0) | **Attribution required** | Free | Excellent, but drag a permanent credit line. Prefer the CC0 Tallbeard bundle |

---

## 8. Comparison table

| | **A. Stylised primitives** | **B. Pixel art 2D** | **C. Low-poly 3D ortho** | **D. Pre-rendered 2.5D** |
|---|---|---|---|---|
| Legibility at 20 px token / 5" screen | ★★★★★ | ★★★☆☆ | ★★☆☆☆ | ★★☆☆☆ |
| Fit to "calm minimal systems game" | ★★★★★ | ★★★☆☆ (reads cozy/retro) | ★★☆☆☆ (reads toy/busy) | ★★☆☆☆ |
| Asset availability for *this* subject | n/a (you author it) | ★★☆☆☆ (Pixel Spaces only) | ★★★★☆ (best supply of all) | ★★★★☆ (same source assets) |
| Hospital theme coverage | ★★★★★ (palette) | ★★★☆☆ | ★☆☆☆☆ (**nobody has one**) | ★☆☆☆☆ |
| Per-level reskin cost | edit a dict | re-author tiles | source a 3rd kit | re-render everything |
| Iteration speed | hot-reload | reimport | scene edit + reimport | **re-render, minutes–hours** |
| Rework to existing code | low (additive) | **high** (`grid.gd` architecture) | **very high** (two pipelines) | **very high** |
| Godot 4.2 risk | none | none | **3 known bug classes** (ortho shadows, MSAA, FBX) | low at runtime |
| Mobile perf risk | none | low | moderate (draw calls solvable; vertex density in a small screen region is not) | low |
| Money | $0–$60 | $2–$15 | $0–$250 | $0–$50 + tooling |
| Time to visible improvement | **3–6 days** | 2–4 weeks | 4–8 weeks | 4–8 weeks |

---

## 9. Licensing summary

| Source | License | Attribution | Commercial | Key restrictions |
|---|---|---|---|---|
| Kenney (2D + 3D + audio, incl. [All-in-1 $19.95](https://kenney.itch.io/kenney-game-assets)) | **CC0** | No | Yes | None |
| Quaternius | **CC0** | No | Yes | None |
| KayKit / Kay Lousberg | **CC0** | No | Yes | None |
| Screaming Brain Studios | **CC0** | No | Yes | None |
| Open Peeps / Humaaans | **CC0** | No | Yes | None |
| Tallbeard "Three Red Hearts" / Music Loop Bundle | **CC0** | No | Yes | Author *requests* no NFT/AI-training use |
| Poly Pizza | **Mixed CC0 / CC-BY** | Per model | Yes | **Check every model** |
| Sonniss GDC bundles | Custom royalty-free | No | Yes | No reselling SFX as-is; **no AI training** |
| Pixabay / Mixkit | Content licence | No | Yes | No standalone resale; no trademarked content |
| Freesound | CC0 / CC-BY / **CC-BY-NC** | Per file | **Not for NC files** | Filter by licence before download |
| OpenGameArt | Free licences only | Per file | Yes | Credits file not authoritative |
| ZapSplat free tier | Standard | **Yes** | Yes | Gold removes attribution permanently for items downloaded while active |
| game-icons.net | CC-BY 3.0 | **Yes** | Yes | Credit authors |
| Kevin MacLeod / Juhani Junkala | CC-BY 4.0 / 3.0 | **Yes** | Yes | Credit line required |
| RhosGFX | Own licence | No | Yes | **No resale; client/commission work needs the $89.99 Commercial Licence** |
| LimeZu (Modern Interiors) | Own licence | **Yes** | Yes | No redistribution |
| Netherzapdos (Pixel Spaces) | Own licence | No | **Paid tier only** | No resale/redistribution; **no AI training**; free tier is non-commercial |
| Cainos / Pixel Frog / Penzilla / Anokolisa | Per-pack | Usually optional | Yes | No resale |
| CraftPix | Own royalty-free | No | Yes | No asset resale |
| GameDeveloperStudio | Own ([licence](https://www.gamedeveloperstudio.com/license.php)) | No | Yes | No royalties, no use caps |
| **Synty POLYGON** | One-time purchase EULA | No | Yes | *"not limited by game engine"* — **Godot is legal**; 5 seats/purchase; must not redistribute as stock art. Godot is **unsupported**, not prohibited |
| **Unity Asset Store** | [EULA](https://support.unity.com/hc/en-us/articles/34387186019988) | No | Yes | **Other engines explicitly permitted.** No redistribution/extractable assets, no cost-sharing, no asset-derived UGC monetisation, watch for "Restricted Asset Terms" |
| **Fab (Epic)** | [Standard Licence](https://www.fab.com/eula) | No | Yes | *"use with any compatible tools"* — not Unreal-limited. No standalone redistribution. Formats are often UE-specific |
| Spine (if ever used) | Editor licence | No | Yes | **$69 Essential / $379 Pro**; Enterprise forced above $500k revenue |
| Fonts (Inter, Rubik, Nunito) | SIL OFL | No (keep licence file) | Yes | — |

**Action item (unchanged from the earlier doc, still not done):** add `CREDITS.md` and log every
imported asset with its licence at import time, not later.

---

## 10. Open questions / unverified

- ITHappy Studios (the only low-poly hospital interior kit found) — site returns 403; prices,
  licences and poly counts unconfirmed. Check via [Fab](https://www.fab.com/) instead.
- Synty publishes no triangle counts; community estimates are props ~100–1,000 tris,
  characters ~1,500–3,000. Unconfirmed.
- SyntyPass ($30–40/mo): what happens to a shipped game after cancellation is not stated on
  the product page. One-time purchases avoid the question entirely.
- Whether a **prebuilt** spine-godot GDExtension for exactly 4.2 is currently published (CI
  builds 4.2/4.3/4.4; docs cite 4.1 and 4.4.1 as examples). Moot unless Spine is adopted.
- Quaternius' Universal Animation Library 2 advertises combat/parkour/farming prominently;
  whether it has a good *standing/waiting/queueing* idle set is unconfirmed. KayKit's 161-anim
  set explicitly does.
- ZapSplat Gold pricing, Incompetech's paid Standard Licence price, jsfxr Pro price — none
  published on reachable pages.
