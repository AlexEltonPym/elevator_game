# Art Asset Research v5 — Furnished Rooms Full of Tiny People

Research for the now-concrete v5 model (`docs/v5-rooms-spec.md`): a mobile-first (portrait
720x1280, Godot **4.2**, `config/features="4.2"` in `project.godot`), cutaway building where
passengers spawn in furnished, multi-cell **rooms** (mostly 2x1, some larger — e.g. a 2x3
"department store"), mill, queue, board elevators docked in the open cells beside the room, ride,
alight, and wander to a new room. This deliberately re-opens the question that
`docs/asset-options-2d-3d.md` (2026-08-12) answered "stay programmer-art" — that doc's rooms were
abstract single cells; v5's rooms are furnished, populated, multi-cell spaces, which is exactly
the condition that doc's own §0 flagged as *"the one thing that would change this answer."*

Confirmed current token sizes from `scripts/v5/`: `grid5.gd:18` — `const CELL := 90.0`, so a 2x1
room is a **180x90 px** furnished area; a 2x3 room is 270x180 px. `passenger5.gd:326-341` draws a
person as body rects around **12-18 px wide, ~18-24 px tall** — matches the brief's "~14x24 px
person." Rooms are big enough to carry real prop detail; people are not.

Date: 2026-08-14. Nothing bought or imported; this is a decision document, written directly to
disk (no code or git changes made in the course of this research).

---

## 0. Recommendation up front

**Partial flip, not a full one.** The furnished-room model genuinely changes the calculus for
**room backdrops** — buy real asset content there. It does **not** change the calculus for the
**people** — at 14x24 px they stay code-drawn primitives with a light icon/color accent, for the
same silhouette-survives-at-small-size reason the earlier doc gave. Nothing found in this pass
contradicts that physics.

**Do this:** keep the existing code-drawn rooms/cars/people architecture, and add a **flat-vector
furnished-room backdrop layer** — a `Sprite2D`/`TextureRect` per room, composited from bought SVG
furniture/structure icons and recolored per theme — sitting *under* the existing dynamic overlay
(dropoff markers, route lines, occupancy tint stay exactly as they are, in code). Spend **$25–60**
on RhosGFX furniture/structure packs + the Kenney All-in-1 as insurance, ~1–2 weeks of
integration, zero architecture rewrite.

**The honest reason not to go further:** 3D-through-ortho now has real furnished-interior supply
for the first time (ithappystudios' hospital kit, Superhive's cartoon interior-scene packs close
the "nobody has a hospital kit" gap from the last doc) — but it is flatly **gated on upgrading
this project from Godot 4.2 to 4.3**, because both engine bugs that killed it last time
(orthographic shadow, Android MSAA black-screen) are confirmed fixed **only in 4.3**, not 4.2
(checked directly against the GitHub issue trackers, below). Even after upgrading, the *people*
still don't benefit — low-poly's "form under lighting" doesn't survive a 14-24 px token, so you'd
be running a full 3D pipeline to arrive at flat colored blobs, which is what primitives already
give you for free. Pixel art (Netherzapdos Pixel Spaces) is the one path that ships an actual
elevator+doors+rooms+tiny-NPC kit today, but costs a `grid5.gd` architecture rewrite and a genre
shift toward cozy/retro.

| Rank | Path | Effort | Cost | Verdict |
|---|---|---|---|---|
| **1** (recommended) | Flat-vector furnished-room backdrops + primitive/icon-accented people | ~1–2 weeks | $25–60 | Best mobile readability, cheapest re-theme, no architecture change |
| **2** | Pixel-art repaint via Netherzapdos Pixel Spaces | 2–4 weeks | $15 | Closest off-the-shelf cutaway-building-with-people kit that exists; forces a TileMap rewrite and a tone shift |
| **3** | Low-poly 3D-through-ortho (ithappystudios + Kenney/KayKit/Quaternius + Crispoly characters) | 4–8 weeks + a Godot 4.2→4.3 upgrade | $0–$180 | Asset gap is finally closed, engine gap is not — needs 4.3, and the payoff mostly lands on room art, which paths 1–2 deliver more cheaply |
| Fallback | Keep pure primitives, add only a game-icons.net furniture-silhouette layer | days | $0 | 70% of path 1's benefit for zero dollars, generic monochrome look |

---

## 1. The Fallout Shelter look — how it's built, and the closest asset routes

**Engine and technique.** Fallout Shelter is a Unity title (Bethesda Game Studios, with
Behaviour Interactive; art direction Istvan Pely). It reads as a flat 2D side-on cutaway but is
built from **3D models viewed through a side-on, near-orthographic camera** — a literal
"dollhouse" vault built from a modular room grid, the same structural idea as this game's cutaway
building. (General confirmation via community discussion of the technique — no official Bethesda
technical postmortem of Fallout Shelter specifically was found in this pass; the closest official
detail is that Pely was Art Director, per the Fallout Wiki developer list.)

**Character style.** Fallout Shelter's dwellers use **chibi/"super-deformed" proportions** — an
enlarged head (roughly 1:1 to 1:2 head-to-body ratio), compressed body, short limbs, and features
reduced to a few legible shapes. This is a deliberate mobile-readability choice: chibi proportions
read as "a person" from farther away and at smaller sizes than realistic proportions do, because
the identifying mass (the head) is exaggerated relative to the rest of the silhouette.

**Why it doesn't transplant directly here.** Fallout Shelter's dwellers occupy far more screen
real estate than this game's tokens ever will — played at a size where a single dweller is tens
of pixels tall with room to read a hairstyle and outfit. This game's passengers are **14x24 px**,
several times smaller, with dozens on screen in a 630x900 px play area on a ~5" phone. At that
scale even a chibi-proportioned model's advantage (a readable head/body split) doesn't survive —
you're back to hue + silhouette being the only channels that work, which is what the game already
draws.

**Closest available asset routes to the look, ranked by fidelity you'd actually keep at this
scale:**

1. **3D-ortho with a modular room kit + chibi/big-head character kit**, rendered exactly like
   Fallout Shelter's own pipeline. Genuinely the most faithful route, and (see §2) the asset
   supply for furnished-room kits has meaningfully improved since the last research pass. Gated
   on Godot 4.3 (§2.2) and its small-token payoff is unproven — the *closest visual match* and
   the *best mobile outcome* are not the same recommendation here.
2. **A flat-vector or pixel approximation of the same idea** — a big-head-small-body silhouette
   drawn/recolored at 2D scale, sitting in a furnished-room backdrop. This is what the
   recommendation in §0 actually is: it borrows Fallout Shelter's *information design* (rooms you
   can see into, tiny legible people, a palette-per-theme) without borrowing its render pipeline,
   because the render pipeline's advantage doesn't survive the token size here.
3. **No shipped asset pack is a plug-and-play "Fallout Shelter kit."** Nothing found — 2D, 3D, or
   pixel — ships a modular vault/cutaway-room system with chibi dwellers ready to drop in; every
   route below is assembled from general-purpose interior + character packs.

---

## 2. The 3D cutout option, re-examined

### 2.1 The furnished-interior supply gap has partially closed

The prior doc's hardest "no" was theming: *nobody ships a hospital kit.* That is no longer fully
true, and the office/cafe/lobby side of the supply was already strong.

| Pack | Creator | License | Formats | Price | Notes |
|---|---|---|---|---|---|
| [Hospital Interior Rooms](https://ithappystudios.com/interiors/hospital-interior-rooms/) (also on [Fab](https://www.fab.com/listings/e71571de-ffe9-46b0-8d40-ef1cc00305a2), [TurboSquid](https://www.turbosquid.com/3d-model/hospital-room/fbx), [CGTrader](https://www.cgtrader.com/3d-models/science/medical/low-poly-interior-14-hospital)) | ithappystudios | Own commercial license (site returns 403 to automated fetch — confirm terms at purchase) | **FBX, OBJ, GLTF**, plus native Unity/Unreal/Blender/C4D/Maya/3DSMax project files | Unverified — check per-storefront | **The first genuine low-poly hospital interior kit found in either research pass.** 1,834 assets, **24 prepared rooms** (A&E, consulting room, delivery room, dispensary, ER…), real-world scale, **rooms sized 4x4x4 m**, **396K tris total across the pack (~216 tri/model)** — very low poly, batches well, **1 material / 1 1024px texture** — ideal for mobile draw-call/VRAM budgets. GLTF export means Godot 4.2 import is a non-issue on the format side |
| [Hospital Floors](https://ithappystudios.com/interiors/hospital-floors/) | ithappystudios | Same as above | Same as above | Unverified | Companion pack — full floor layouts rather than single rooms |
| [Hospital Isometric Rooms](https://superhivemarket.com/products/hospital-1) | (Superhive/Blender Market) | Blender Market Standard License — commercial use permitted, no resale of raw source files (typical Superhive terms; confirm on product page) | `.blend` native; check product page for FBX/glTF export inclusion | Unverified (fetch blocked, 403) | Isometric framing, not straight side-on — would need camera/asset re-angling |
| [Interior 4 / 6 / 7 Asset Pack](https://superhivemarket.com/products/interior-4) — "Interior Scenes with over 1390 3D models" | (Superhive/Blender Market) | Same Standard License caveat | `.blend`; verify export formats before buying | Unverified | Cartoon low-poly **office, cafe, school** scene packs — closes the office/cafe side further |
| [10 Cartoon-Style Low Poly 3D Room Interiors Pack](https://superhivemarket.com/products/cartoon-rooms-) | (Superhive/Blender Market) | Same caveat | `.blend`; verify exports | Unverified | Ten pre-composed cartoon room interiors — a fast way to get several distinct furnished rooms without hand-assembling from a modular kit |
| [Office Rooms 3D Model Pack](https://superhivemarket.com/products/office-1) | (Superhive/Blender Market) | Same caveat | `.blend`; verify exports | Unverified | 24 prepared rooms: working room, meeting room, kitchen, lounge, training room, cafe |

⚠️ All Superhive/Blender Market pages 403'd automated fetch in this pass (both direct fetch and
via search snippets) — **prices and exact export-format lists are unverified and must be checked
manually before purchase.** The ithappystudios page also 403'd directly; the specs above come
from search-indexed snippets of the same page, so treat the tri-count/room-count figures as
"reported," not independently confirmed on-page.

**Still unchanged from the last pass:** Kenney 3D (CC0 — [Furniture Kit](https://kenney.nl/assets/furniture-kit),
[Building Kit](https://kenney.nl/assets/building-kit), [Modular Buildings](https://kenney.nl/assets/modular-buildings)),
Quaternius (CC0 — [Ultimate House Interior](https://quaternius.com/packs/ultimatehomeinterior.html),
[Ultimate Modular Sci-Fi](https://quaternius.com/packs/ultimatemodularscifi.html)), and KayKit (CC0 —
[Furniture Bits](https://kaylousberg.itch.io/kaykit-furniture-bits)) remain the free baseline for
office/lobby/spaceship-vault theming, all GLB/GLTF-friendly, all CC0. **Synty POLYGON Office**
($49.99, [syntystore.com/products/polygon-office-pack](https://syntystore.com/products/polygon-office-pack) —
772 assets, 626 props, 128 modular building pieces incl. a modular stairwell) is still the richest
single office kit; **Synty POLYGON Town** ($30–40/mo via SyntyPass or per-pack,
[syntystore.com/products/polygon-town-pack](https://syntystore.com/products/polygon-town-pack) —
125 buildings, 412 props, 99 environment pieces, 9 characters) covers a lobby/street exterior look
if ever needed. Synty's nearest hospital-adjacent pack is still **POLYGON Horror Asylum** ($99.99)
— tonally wrong (deliberately unsettling) for a calm sim.

### 2.2 Godot 4.2 vs 4.3 — checked directly against the issue trackers

This project's `project.godot` pins `config/features="4.2"`. Both blockers the last doc flagged
were re-checked against GitHub directly in this pass:

- **[godotengine/godot#78422](https://github.com/godotengine/godot/issues/78422)** — orthographic
  camera + shadows broken. Fixed by **[PR #92287](https://github.com/godotengine/godot/pull/92287)**,
  milestoned and merged for **Godot 4.3**. **4.2 does not have this fix.**
- **[godotengine/godot#81910](https://github.com/godotengine/godot/issues/81910)** — MSAA
  black-screens on Android/Vulkan Mobile when no transparent objects are in the scene (exactly
  the case for an opaque low-poly interior). Confirmed **closed**, milestoned **4.3**, fixed via
  PR #84169. **4.2 does not have this fix either.**
- A related but *separate* regression, **[#120457](https://github.com/godotengine/godot/issues/120457)**
  → **[PR #120711](https://github.com/godotengine/godot/pull/120711)**, is a **4.7-era**
  regression in ortho shadow culling, cherry-picked to 4.7.1/4.8 — irrelevant to a 4.2/4.3
  decision, noted here only so it isn't confused with the 4.3 fix above.

**Verdict: 3D-through-ortho is not viable on Godot 4.2 for this game — it requires upgrading to
at least 4.3.** That upgrade itself looks tractable: per the [official 4.2→4.3 migration
guide](https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.3.html),
*"for most games and apps made with 4.2 it should be relatively safe to migrate,"* and the listed
breaking changes (binary serialization of scripted Objects/typed Arrays, the high-level
multiplayer protocol, `Decal` modulate color going sRGB→linear, a C# enum rename) don't touch
anything this GDScript, non-multiplayer, non-Decal, immediate-mode-`_draw` project uses. If 3D is
ever pursued, the 4.3 upgrade is a separate, low-risk, one-time cost — do it deliberately, not as
a side effect of an asset purchase.

**Even on 4.3, the readability doubt from the last doc stands unchanged and was not contradicted
by anything found this pass:** low-poly reads through bevels and baked lighting, both of which
matter far less at a 14-24 px token with shadows tuned conservatively for mobile. Godot's own
mobile-3D guidance still specifically warns against dense geometry concentrated in a small part of
the screen — a literal description of a crowd of tiny passengers in a 630x900 px play area.

### 2.3 The little-people side of 3D, specifically

- **[KayKit Character Animations](https://kaylousberg.itch.io/kaykit-character-animations)** —
  free, CC0, **161 humanoid animations** (idle/walk/wave/sit…) in GLTF, still the best free motion
  library; needs re-skinning per role since KayKit's own character rosters are adventurer/skeleton
  themed, not office/hospital.
- **[Kenney Mini Characters](https://kenney.nl/assets/mini-characters)** — CC0, 12 characters x 32
  animations each, **including wheelchair-user animations** (useful for a patient/visitor role),
  FBX + PNG skin atlases (not native GLB — Kenney's own
  [import guide](https://kenney.nl/knowledge-base/game-assets-3d/importing-characters-and-animations)
  covers the FBX→Godot path). Flat, simple palette per character — cheap to reskin per role.
- **[Quaternius Universal Animation Library 2](https://quaternius.com/packs/universalanimationlibrary2.html)**
  — free, CC0, 130+ animations, FBX + GLB, explicitly stated compatible with a universal humanoid
  rig usable in Godot.
- **[Crispoly Characters Mini](https://imphenzia.com/crispoly-characters-mini)** (Imphenzia) — new
  find this pass. **$29**, commercial use supported, **135 rigged low-poly characters sharing one
  armature and one animation set** (so adding a new role is a re-skin, not a re-rig), deliverables
  are a master `.blend` **plus FBX (Unity/Unreal/Godot-tuned) and GLB (glTF2) exports**, with a
  bundled Python export script that regenerates all characters/animations with Godot-correct
  settings. No dedicated Godot demo project yet (per the creator's own page), but the GLB export
  path is exactly what Godot 4.2/4.3 wants. Uses a palette-texture colorization technique the
  creator states stays sharp at any zoom — worth a look specifically *because* the shared-armature
  structure would make 4 role-variants (visitor/patient/exec/courier) cheap to produce once bought.

---

## 3. The 2D flat/vector option

### 3.1 Still no shipped cutaway-building kit — re-confirmed

Searched again this pass for "cutaway," "cross-section," and "dollhouse" flat-vector *game asset*
packs specifically (not stock illustration). Result unchanged from the last doc: this remains
**stock-illustration territory (iStock, 123RF, Vecteezy)**, not a purchasable, importable game
asset pack. Nobody sells a flat-vector cutaway-room kit. This is the one place the earlier
research holds completely.

### 3.2 But a *furnished room* only needs 2–4 props, and that's buyable now

The structural fact that changes the calculus: a v5 room is 180-270 px, not a bare 90 px cell. It
doesn't need a *kit*; it needs a handful of recognizable, recolorable prop icons per theme,
composited by hand into a room backdrop. That's a much smaller ask than "find a cutaway kit," and
it's well served:

| Source | License | Price | Notes |
|---|---|---|---|
| [RhosGFX Vector Furniture](https://rhosgfx.itch.io/) | Own license — commercial OK, no resale, client/commission work needs the $89.99 Commercial Licence | $7.99 (also a cheaper [Vector Furniture Pack](https://rhosgfx.itch.io/vector-furniture-pack), $4.99) | SVG sources — recolor to the per-theme palette, rasterize at 2x on import exactly as the prior doc's §2.4 describes |
| RhosGFX Vector Structures / PRO | Same license | $4.99 / $6.99 | Wall/floor/window dressing to sit behind furniture |
| [game-icons.net](https://game-icons.net/) | CC-BY 3.0 — credit authors | Free | 4,100+ monochrome SVGs incl. briefcase, bed, syringe — already in the project's plan per `docs/asset-research.md`; the cheap fallback for one-off props a themed pack doesn't cover |
| [Kenney All-in-1](https://kenney.itch.io/kenney-game-assets) | CC0 | $19.95 | Insurance bundle; recent additions include Isometric Vector Buildings and a Sketch Town Expansion, but Kenney has no dedicated flat furniture-icon set — use it for UI chrome and one-off filler, not room props |
| [LimeZu Modern Interiors](https://limezu.itch.io/moderninteriors) | Own license, credit required, no redistribution | PWYW, $1.50+ | **Reference only, not a direct source** — this is a superb office/hospital/waiting-room/reception pack, but it's **top-down RPG projection**. Don't buy it expecting to drop tiles into a side-view cutaway; at most, hand-trace 2-3 props per theme for style reference. Re-confirms the prior doc's warning that this is the single most common asset-buying mistake for this game's genre |

### 3.3 The little people, flat-vector

Unchanged conclusion, restated because it's now the load-bearing one: **Kenney Shape Characters**
(CC0, modular geometric parts) or the game's existing hand-drawn primitives remain the right base
at 14-24 px. What changes is that it's now worth spending a *little* on distinguishing accessories
— RhosGFX Vector Avatars ($6.99) or game-icons.net icons (briefcase tick for exec, syringe/drip
for patient, parcel for courier) layered onto the same silhouette-plus-hue system already in
`passenger5.gd`. This is a design pass on top of what exists, not a pack replacing it.

---

## 4. The pixel art option

### 4.1 Netherzapdos Pixel Spaces — grown substantially since the last pass

[Pixel Spaces](https://netherzapdos.itch.io/pixel-spaces) is still the single closest thing to a
cutaway-building-with-tiny-people kit that exists anywhere, and it has grown:

- **1,200+ assets** now (up from 1,454 individual pieces cited last pass, packaging has shifted —
  the pack description now states 1,200+ core assets plus **14 free expansions**).
- Confirmed live expansions found this pass beyond what the last doc saw: **Hospital Expansion**
  (+54 assets, shipped), **Grocery Expansion** (+46 assets), **Police Station**, **Streets**,
  **Backgrounds**, **UI**, **Animations**, **Gamer Room** — the theme coverage (office/hospital
  via Grocery-as-department-store-analog/cafe) now maps unusually well onto this game's planned
  room types (lobby, office, department store, cafe, hospital-ish).
- Still has **doors, elevator, stairs** pieces baked in, and **30 animated NPCs** at a 16 px base
  grid (32 px characters) — a real match for "little people who spawn in furnished rooms."
- **Price: $15** (running a 34% off summer-2026 sale at time of writing) for the commercial tier;
  free tier is **non-commercial only**. License: usable in any commercial or non-commercial
  project, modifiable, **no resale/redistribution even if modified, no AI training use**.
- **PNG format**, explicitly Unity/Godot-targeted.

### 4.2 The cost is unchanged and still real

Adopting this means moving `grid5.gd` off immediate-mode `_draw` onto a TileMap/Sprite2D
architecture, and re-implementing every dynamic overlay (dropoff markers, route highlighting,
occupancy tint, drag preview) as sprites or shaders rather than draw calls. Budget **2-4 weeks**,
and accept that the tone shifts from "calm systems diagram" toward "cozy/retro," which is a
genre choice, not just an art choice — same caveat the last doc raised, unchanged by the new
expansions.

### 4.3 Companion pixel finds

Nothing new displaced Pixel Spaces as the anchor. General "tiny NPC" pixel packs surfaced this
pass ([Tiny Neighbours](https://vryell.itch.io/tiny-neighbours) — 16x16, 15 NPCs, 3 skin tones;
various "Tiny Tales"/"Tiny Heroes" packs on itch.io) are all **top-down or platformer projection**,
same mismatch problem as LimeZu in §3.2 — useful only as inspiration, not drop-in assets, since
none are authored for a side-on cutaway.

---

## 5. The little people specifically — cross-style summary

| Style | Best source | Format | License/price | Role-variant cost |
|---|---|---|---|---|
| **3D** | KayKit Character Animations (motion) + Kenney Mini Characters or Crispoly Characters Mini (bodies) | GLTF/GLB/FBX | CC0 free (KayKit, Kenney) / $29 (Crispoly, commercial) | Re-skin per role — cheap with Crispoly's shared-armature design, moderate with Kenney's separate atlases |
| **2D flat** | Kenney Shape Characters (base) + RhosGFX Vector Avatars or game-icons.net (accessories) | SVG/PNG | CC0 (Kenney) + $6.99 (RhosGFX) or free w/ credit (game-icons.net CC-BY 3.0) | Cheapest — palette + one accessory icon per role |
| **Pixel** | Netherzapdos Pixel Spaces' 30 animated NPCs | PNG, 32x32 | $15 commercial tier | Built-in variety, but limited to what the pack ships; custom roles need hand-pixeling to match |

**Animation sources, restated from `docs/asset-options-2d-3d.md` §6 and re-confirmed as still
correct at this token size regardless of which style is chosen:** for the *people* specifically,
`AnimationPlayer`/`Tween` on code-drawn primitives remains right — a 14-24 px token has no budget
for a skeletal rig's visual payoff. If a style is adopted for the room *backdrop*, the people
inside it can stay exactly as animated as they are today; nothing here argues for re-rigging the
passengers themselves, in any of the three styles.

---

## 6. Elevator cars, UI, and audio — briefly

- **Elevator car:** stays code-drawn regardless of which room-art path is chosen. The car docks in
  the *open* cell beside a room (per `v5-rooms-spec.md`), never inside the furnished area, so it
  never needs to match the room's asset fidelity — the door-phase/capacity-pip/ghost-state logic
  that made packs a poor fit last time (`docs/asset-options-2d-3d.md` §1) is unchanged. If a
  furnished-room backdrop is adopted, consider only a matching icon accent (RhosGFX/Kenney) on the
  door frame for visual continuity with the room it serves.
- **UI:** unchanged recommendation — Kenney UI Pack (CC0, free) + a Godot `Theme` resource
  (`Themey`, MIT/CC0) remains the cheapest real upgrade, independent of the room-art decision.
- **Audio:** unchanged from `docs/asset-options-2d-3d.md` §7 — Sonniss #GameAudioGDC (free, custom
  royalty-free, no AI training) for one-off SFX, Bfxr2/jsfxr for UI tones, Tallbeard/Abstraction
  CC0 loops for music. Nothing in this pass changes that picture; no new audio research was
  needed since the furnished-room pivot doesn't touch sound design.

---

## 7. Ranked recommendation, in full

**Does the furnished-rooms-full-of-tiny-people model flip the earlier "stay programmer-art"
verdict?** Partially, and specifically at the *room* level, not the *people* level:

- **Room backdrops (180-270 px furnished cells): flip to "buy real content."** This is exactly
  the condition the last doc's §0 named as the thing that would change the answer, and it has
  happened. A composited flat-vector or pixel furniture layer now reads as a real office/hospital/
  cafe rather than a palette-swapped rect, at a size where that detail survives.
- **People (14x24 px): verdict holds, unchanged.** Nothing found in this pass — not Fallout
  Shelter's real pipeline, not new 3D character kits, not pixel NPC packs — beats hue + silhouette
  + a light accessory icon at this token size. The reasoning is unchanged from the prior doc: the
  identifying channels that survive at 14-24 px are exactly the channels primitives are made of.
- **Elevator car, UI, audio: fully unchanged**, addressed in §6.

### Top 3 concrete art paths

1. **Flat-vector furnished rooms + primitive/icon-accented people (recommended).** Composite room
   backdrops from RhosGFX furniture/structure SVGs + game-icons.net accents, palette-per-theme
   exactly as `docs/asset-research.md`'s original recipe describes, layered under the existing
   dynamic `_draw` overlay. **Effort:** ~1-2 weeks, additive, no architecture change. **Cost:**
   $25-60. **Per-theme reskin:** swap a handful of SVGs + a palette dict — cheapest of the three.
   **Mobile readability:** best — the people keep their proven silhouette+hue legibility, the
   rooms get real detail at a size where it survives. **PC scale-up:** clean — SVG rasterizes
   sharp at any resolution (author at 2x per the prior doc's Godot-SVG note).

2. **Pixel-art repaint via Netherzapdos Pixel Spaces.** The only path with an actual off-the-shelf
   elevator+doors+furnished-rooms+animated-tiny-NPCs kit, now stronger than last researched
   (hospital + grocery + police + streets expansions live). **Effort:** 2-4 weeks — forces
   `grid5.gd` off immediate-mode `_draw` onto TileMap/Sprite2D, and every dynamic overlay must be
   re-authored as sprites/shaders. **Cost:** $15. **Per-theme reskin:** moderate — the pack covers
   several themes directly, others need style-matched custom pixel work. **Mobile readability:**
   good at 16-32 px if the metrics are re-derived to an integer pixel grid (today's 90 px cells
   don't align to one). **PC scale-up:** needs nearest-neighbor filtering, standard for the genre.
   **Honest cost not to understate:** this also changes the game's tone toward cozy/retro, a
   genre decision as much as an art one.

3. **Low-poly 3D-through-ortho.** The asset-supply objection from last time is real but no longer
   fatal — ithappystudios' Hospital Interior Rooms (1,834 assets, 24 rooms, very low tri count,
   GLTF-native) plus Superhive's cartoon office/cafe interior-scene packs plausibly cover all of
   lobby/office/department-store/cafe/hospital. The **engine** objection is now precisely
   characterized rather than hand-waved: both blocking bugs (ortho shadows #78422, Android MSAA
   #81910) are confirmed fixed in Godot **4.3**, confirmed absent in the project's current **4.2**
   pin — this path requires a deliberate engine upgrade first, which the official migration guide
   calls low-risk for a project like this one. Even after upgrading, the *payoff is uncertain*:
   the small-token readability doubt from the prior doc (§3.3 of `asset-options-2d-3d.md`) was not
   contradicted by anything found here — low-poly's form-under-lighting advantage still doesn't
   plainly survive 14-24 px. **Effort:** 4-8 weeks + the 4.3 upgrade. **Cost:** $0-$180+ depending
   on kit selection (ithappystudios pricing unverified; Crispoly Characters Mini $29 for
   characters; CC0 Kenney/KayKit/Quaternius free for the rest). **Per-theme reskin:** most
   expensive of the three — a distinct sourced kit per theme, style-matched by hand. **Verdict:**
   worth prototyping only if the room *backdrop* is judged to specifically need 3D depth/parallax
   that flat art can't deliver — otherwise paths 1-2 get more of the same visible improvement for
   less money and less engine risk.

**Honest zero-budget option:** if no purchase is wanted at all, add only a **game-icons.net**
furniture-silhouette layer (already CC-BY-3.0-licensed and in the project's existing plan) behind
the code-drawn people, recolored per theme. This captures roughly 70% of path 1's visible benefit
for $0 — the cost is a slightly generic, monochrome-icon look versus a fully illustrated room.

---

## 8. Comparison table

| | **1. Flat-vector rooms** | **2. Pixel-art repaint** | **3. Low-poly 3D ortho** |
|---|---|---|---|
| Room-backdrop legibility at 180-270 px | ★★★★★ | ★★★★☆ (cozy, not clinical) | ★★★☆☆ (needs 4.3, lighting-dependent) |
| People legibility at 14-24 px | ★★★★★ (unchanged primitives) | ★★★★☆ (pack ships tiny NPCs) | ★★☆☆☆ (form-under-lighting doesn't survive scale) |
| Asset supply for office/hospital/cafe/lobby | ★★★★☆ (compose from icons) | ★★★★★ (Pixel Spaces covers most directly) | ★★★★☆ (gap newly closed, still assemble-it-yourself) |
| Engine risk on current Godot 4.2 | None | None | **Requires 4.2→4.3 upgrade** (two confirmed-fixed-in-4.3 bugs) |
| Rework to existing code | Low — additive backdrop layer | **High** — `grid5.gd` architecture change | **Very high** — new render pipeline alongside the 2D overlay |
| Per-theme reskin cost | Cheapest (SVG + palette) | Moderate (pack-dependent) | Most expensive (source + style-match per theme) |
| Cost | $25-60 | $15 | $0-$180+ |
| Time to visible improvement | 1-2 weeks | 2-4 weeks | 4-8 weeks + upgrade |

---

## 9. Licensing summary (new/changed entries this pass)

| Source | License | Attribution | Commercial | Key restrictions |
|---|---|---|---|---|
| ithappystudios (Hospital Interior Rooms, Hospital Floors) | Own commercial license | Unverified — check at purchase | Presumed yes (marketed as game-ready) | **Site returns 403 to automated tools; verify terms manually before buying** |
| Superhive/Blender Market (Interior 4/6/7, Cartoon Rooms, Office Rooms, Hospital Isometric Rooms) | Blender Market Standard License (typical) | No (typical) | Yes (typical) — no resale of raw `.blend` source | **Product pages 403'd automated fetch this pass — verify price and exact export formats (FBX/glTF inclusion) before buying** |
| Crispoly Characters Mini (Imphenzia) | Own license | No | Yes, explicitly commercial-use-supported | $29 one-time; no Godot demo project yet, but ships Godot-tuned GLB directly |
| Netherzapdos Pixel Spaces | Own license (unchanged from prior doc) | No | **Paid tier ($15) only** | No resale/redistribution even if modified; **no AI training**; free tier is non-commercial only |
| RhosGFX (Vector Furniture, Structures, Avatars) | Own license (unchanged from prior doc) | No | Yes | No resale; client/commission work needs the $89.99 Commercial Licence |
| game-icons.net | CC-BY 3.0 (unchanged) | **Yes** | Yes | Credit authors |
| Kenney (all packs, incl. Mini Characters, All-in-1) | CC0 (unchanged) | No | Yes | None |
| KayKit / Quaternius | CC0 (unchanged) | No | Yes | None |
| Synty POLYGON (Office/Town/Horror Asylum) | One-time purchase EULA (unchanged) | No | Yes | Not engine-limited; Godot support is per-pack, not universal — check each product page |

All other sources are unchanged from `docs/asset-options-2d-3d.md` §9 and `docs/asset-research.md`
§6 — not repeated here to avoid drift between three documents; treat those two as still current
for Kenney/Quaternius/KayKit/audio/fonts licensing.

---

## 10. Open questions / unverified (this pass)

- ithappystudios Hospital Interior Rooms / Hospital Floors — price and exact license text
  unconfirmed; the site 403'd both direct `WebFetch` and reconfirmation, so the room-count and
  tri-count figures above come from search-indexed snippets of the same page, not a direct read.
  Check via the Fab, TurboSquid, or CGTrader mirror listings before committing budget.
- Superhive/Blender Market interior packs (Interior 4/6/7, Cartoon Rooms, Office Rooms, Hospital
  Isometric Rooms) — prices and precise export-format lists (does the deliverable include
  FBX/glTF, or only `.blend`, requiring your own Blender re-export step?) are unverified; all
  product-page fetches returned 403 in this pass.
- Crispoly Characters Mini's 135 characters — role/outfit variety (does it include anything
  office/medical-coded, or is it a generic base needing full re-skinning for this game's four
  roles?) was not enumerated on the page fetched; check the character gallery before buying.
- Whether Godot 4.3's ortho-shadow fix (#78422/PR #92287) is fully sufficient for this game's
  specific "whole small building, fixed far plane" framing, or whether the mobile depth-precision
  and transparency-sorting caveats from `docs/asset-options-2d-3d.md` §3.2 (16-bit depth buffer,
  per-node-origin transparency sort) still bite independently — those were not re-tested here and
  should be treated as still-open even after a hypothetical 4.3 upgrade.
