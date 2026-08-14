# Art Asset Options — A Shopping Survey (v5 Rooms)

Purpose: real, buyable/downloadable packs to look at and compare, not a verdict. Both constraints
from `docs/asset-research-v5.md` are lifted for this pass: **the engine can be upgraded** (Godot
4.3+ if a style wants it — 3D-through-ortho is a real option here), and **the game can be scaled up**
(bigger rooms, bigger characters, zoom, scroll), so nothing below is filtered out for "too big" or
"too 3D." Go look at the storefronts — every pack has preview images and most have video.

Five style directions, each with 2-4 concrete packs covering the four asset needs: furnished
cutaway **rooms**, small-but-bigger **characters** (visitor / patient / exec / shopper / delivery
man), **elevator** cars, and **UI**.

---

## Comparison table

| Style | Rooms pack | Character pack | Vibe | ~Cost to art the game | License | Reference game | Engine need |
|---|---|---|---|---|---|---|---|
| **Low-poly 3D dollhouse** | Synty POLYGON Office / Town / Shops, or CC0 Kenney+Quaternius+KayKit | Synty POLYGON City Characters, Kenney Mini Characters, Crispoly Characters Mini | Fallout Shelter / Two Point cutaway diorama, baked lighting, chunky low-poly | $0 (CC0-only) to ~$350 (full Synty roster incl. Shops) | Mixed: CC0 (Kenney/Quaternius/KayKit) + Synty one-time EULA | **Fallout Shelter**, **Two Point Hospital** | Godot **4.3+** (ortho-shadow/MSAA fixes); Synty now ships native **Godot 4.5/4.6** projects |
| **Flat vector / clean 2D** | RhosGFX Vector Furniture + Structures | RhosGFX Vector Avatars + Kenney Shape Characters | Crisp, poster-flat, high-contrast silhouettes | $25-60 | RhosGFX own license (commercial OK, no resale) + CC0 (Kenney) | **Project Highrise** (literal SimTower-vectorized cutaway tower), **Mini Motorways** | None — works today on Godot 4.2 |
| **Pixel art (cozy sim)** | Netherzapdos Pixel Spaces + LimeZu Modern Interiors | Pixel Spaces' 30 built-in NPCs | Warm, retro, chunky-cute | $15-25 | Own licenses, commercial OK, no resale/AI-training | **SimTower / Yoot Tower** (direct genre ancestor, literally elevators in a cutaway pixel tower), **Stardew Valley** | None — works today, but is a bigger internal rework (TileMap vs current `_draw`) |
| **Isometric** | pixel_Salvaje Isometric Interiors + Kenney Isometric Buildings | (compose from isometric character packs — thinner supply) | Diorama-from-above, dollhouse-viewed-from-a-corner | $18-40 | Own license (Isometric Interiors) + CC0 (Kenney) | **Two Point Hospital** (semi-isometric reads), **Islanders** | None, but this is a camera-angle pivot away from your current side-on cutaway |
| **Hand-drawn / illustrated** | Scattered — shubibubi Cozy Interior, custom-commission | Scattered — POMPACK, ForsakenVoid | Warm, storybook, painterly | $0-30 off-the-shelf, or commission-priced for true cohesion | Varies per creator | **Unpacking**, **A Short Hike** | None — but weakest buyable-pack supply of the five |

---

## 1. Low-poly 3D dollhouse (Fallout Shelter / Two Point / Sims-build vibe)

The furnished-interior supply for this look is genuinely good right now, and — new since the last
research pass — **Synty now ships native Godot 4.5/4.6 project packages**, not just raw FBX/GLTF
you import by hand.

### Rooms / interiors

| Pack | Covers | Price | License | Format |
|---|---|---|---|---|
| [Synty POLYGON Office Pack](https://syntystore.com/products/polygon-office-pack) | 772 assets: 128 modular building pieces, 600+ props, 18 office characters, full demo scene | $49.99 | Synty one-time purchase EULA (5 seats) | FBX + native **Godot 4.6.2**, Unity 2022.3+, Unreal 5.3+ |
| [Synty POLYGON Town Pack](https://syntystore.com/products/polygon-town-pack) | 125 buildings, 412 props, 99 environment pieces, 9 characters — lobby/street/exterior dressing | $49.99 | Same EULA | FBX + native **Godot 4.5.1**, Unity, Unreal |
| [Synty POLYGON Shops Pack](https://syntystore.com/products/polygon-shops-pack) | 1,933 prefabs: supermarkets, fast food, gyms, salons, general stores — direct hit for the "store/delivery bay" room type; 14 characters incl. shopkeepers | $199.99 (currently sold out — check restock) | Same EULA | FBX + native **Godot 4.6.2** |
| [ithappystudios Hospital Interior Rooms](https://ithappystudios.com/interiors/hospital-interior-rooms/) (mirrors: [Fab](https://www.fab.com/listings/e71571de-ffe9-46b0-8d40-ef1cc00305a2), [TurboSquid](https://www.turbosquid.com/3d-model/hospital-room/fbx), [CGTrader](https://www.cgtrader.com/3d-models/science/medical/low-poly-interior-14-hospital)) | 24 prepared rooms (ER, consulting, X-ray, operating…), 396K tris total, 1 material/1024px texture — cheap on mobile | Unverified — check per storefront; site 403s automated fetch | Own commercial license — confirm at purchase | FBX, OBJ, **GLTF**, plus native Unity/Unreal/Blender/C4D/Maya/3DSMax |
| [Kenney Furniture Kit](https://kenney.nl/assets/furniture-kit) + [Building Kit](https://kenney.nl/assets/building-kit) | 100+ furniture models, 80+ wall/floor/door/window pieces | Free | CC0 | OBJ, FBX, glTF |
| [Quaternius Ultimate House Interior Pack](https://quaternius.com/packs/ultimatehomeinterior.html) | 120+ models: kitchen, bathroom, doors, windows | Free | CC0 | FBX, OBJ, glTF, Blend |
| [KayKit Furniture Bits](https://kaylousberg.itch.io/furniture-bits) | 50+ low-poly furniture models | Free | CC0 | GLB |
| [Superhive Cartoon Rooms / Office Rooms / Interior 4-6-7](https://superhivemarket.com/products/cartoon-rooms-) | 10 pre-composed cartoon interiors; separate office/cafe/school scene packs | Unverified — pages 403 automated fetch, check manually | Blender Market Standard License (commercial OK, no `.blend` resale) | `.blend` — verify FBX/glTF export before buying |

### Characters (visitor / patient / exec / shopper / delivery man)

| Pack | Covers | Price | License | Format |
|---|---|---|---|---|
| [Synty POLYGON City Characters](https://syntystore.com/products/polygon-city-characters-pack) | 19 characters incl. **shop keeper, paramedic, gangster, tourist, hot dog guy** — genuinely close to your role list already | $29.99 | Synty EULA | FBX + native Godot project |
| [Kenney Mini Characters](https://kenney.nl/assets/mini-characters) | 12 characters x 32 anims each, **including wheelchair-use animations** (patient/visitor role) | Free | CC0 | FBX + PNG skin atlases |
| [KayKit Character Animations](https://kaylousberg.itch.io/kaykit-character-animations) | 161 humanoid animations (idle/walk/wave/sit) | Free | CC0 | GLTF |
| [Quaternius Universal Animation Library 2](https://quaternius.com/packs/universalanimationlibrary2.html) | 130+ animations, universal humanoid rig | Free | CC0 | FBX, GLB |
| [Crispoly Characters Mini](https://imphenzia.com/crispoly-characters-mini) | 135 characters, **one shared armature/animation set** — cheap to spin up 4-5 role variants once bought | $20 | Own license, commercial-use supported | Blend + Godot-tuned FBX/GLB export script |

**Vibe & reference:** Fallout Shelter's chibi dwellers in a literal dollhouse vault; Two Point
Hospital's cutaway-with-lighting look. This is the most visually rich option and the only one that
gets real baked lighting/depth in the room shots.

---

## 2. Flat vector / clean 2D (Mini Motorways / Two Dots polish)

The best-matched reference game for this whole project might be **Project Highrise** — reviewers
describe its look as literally *"they took the pixels of SimTower and vectorised them"* — flat,
pastel, high-DPI-crisp, and it's a tower/elevator sim. Worth a direct look as a mood board.

### Rooms / furniture / structure

| Pack | Covers | Price | License | Format |
|---|---|---|---|---|
| [RhosGFX Vector Furniture Pack](https://rhosgfx.itch.io/vector-furniture-pack) | 250+ assets across 11 categories: seating, kitchen, office, storage, tech, lighting… | $7.99 | Own license — commercial OK, no resale, no AI training | PNG8 |
| [RhosGFX Vector Furniture Pack PRO](https://rhosgfx.itch.io/vector-furniture-pack-pro) | Same content + SVG source files | $11.99+ | Same | SVG |
| RhosGFX Vector Structures / PRO | Wall/floor/window dressing behind the furniture | $4.99 / $6.99 | Same | PNG / SVG |
| [RhosGFX RPG Interiors](https://rhosgfx.itch.io/rpg-interiors) | Companion room-shell pack in basic/rustic themes | Check page | Same | PNG/SVG |
| [Kenney All-in-1](https://kenney.itch.io/kenney-game-assets) | Insurance bundle — UI chrome, isometric buildings, filler props | $19.95 | CC0 | Mixed |

### Characters

| Pack | Covers | Price | License | Format |
|---|---|---|---|---|
| [RhosGFX Vector Avatars](https://rhosgfx.itch.io/vector-avatars) | Modular facial features + several prebuilt roles | $6.99 | Own license, commercial OK | PNG |
| [RhosGFX Vector Avatars PRO](https://rhosgfx.itch.io/vector-avatars-pro) | Same, SVG source | $9.99+ | Same | SVG |
| [Kenney Shape Characters](https://kenney.nl/assets/shape-characters) | Modular geometric-part people — cheap to recolor per role | Free | CC0 | PNG/SVG |

### UI

| Pack | Covers | Price | License |
|---|---|---|---|
| [Kenney UI Pack](https://kenney.nl/assets/ui-pack) | 430 UI assets | Free | CC0 |

**Vibe & reference:** Project Highrise, Mini Motorways, Two Dots — poster-flat shapes, big color
blocks, no gradients needed. Cheapest per-theme reskin of the five (swap SVGs + a palette).

---

## 3. Pixel art (cozy sim)

The closest thing that exists anywhere to an off-the-shelf **cutaway-building-with-elevators-and-
tiny-people** kit. And there's a genre-perfect reference: **SimTower** (and its sequel *Yoot
Tower*) is a pixel-art cutaway tower where you literally route elevators between floors — the
direct ancestor of this game, rendered exactly in this style.

| Pack | Covers | Price | License | Format |
|---|---|---|---|---|
| [Netherzapdos Pixel Spaces](https://netherzapdos.itch.io/pixel-spaces) | 1,454 assets: building/wall tiles, furniture, objects, **animated elevators + doors + stairs baked in**, 15M/15F customizable NPCs, 16 free expansions incl. **Hospital, Grocery, Cafe, Police Station** | $15 (name-your-price min, sale runs periodically) | Own license — commercial OK, modify freely, no resale, no AI training | PNG, 16x16 base grid |
| [LimeZu Modern Interiors](https://limezu.itch.io/moderninteriors) | Thousands of furniture pieces across office/hospital/museum/shop/restaurant themes; character generator: 100+ outfits, 200 hairstyles, 9 skin tones | $1.50+ (pay-what-you-want) | Own license, credit required, no redistribution | PNG, 16x16/32x32/48x48 |
| [LimeZu Modern Office — Revamped](https://limezu.itch.io/modernoffice) | Companion office-specific tileset | Check page | Same | PNG |
| Cainos-style "modern office" packs ([itch.io tag: office](https://itch.io/game-assets/tag-office)) | Browse — several 16x16 office packs with 55+ assets and 12+ staff characters surfaced under this tag | Varies, mostly $5-15 | Varies per creator | PNG |

**Note both packs use a top-down/RPG-Maker-style tile grid natively** — the elevator/door pieces
in Pixel Spaces are the useful side-on exception; the furniture in both packs recolors/recomposes
cleanly into a side-view cutaway room even though the source projection is top-down.

**Vibe & reference:** SimTower, Yoot Tower, Stardew Valley — warm, chunky, nostalgic. The one
option that ships doors/elevators/tiny-NPCs as a matched set out of the box.

---

## 4. Isometric

Worth naming plainly: isometric is a camera-angle pivot away from your current straight-on
cutaway — a diorama-viewed-from-a-corner rather than a doll's-house-viewed-from-the-front. Supply
here is thinner and more scattered than the other three, but there are real packs.

| Pack | Covers | Price | License | Format |
|---|---|---|---|---|
| [Isometric Interiors — Tileset](https://pixel-salvaje.itch.io/isometric-interiors) | 350+ sprites, functional doors, wall/floor variety | $18 (name-your-price min) | Own license, commercial OK, no resale | PNG |
| [Kenney Isometric Tiles — Buildings](https://kenney.nl/assets/isometric-tiles-buildings) | 128 modular isometric building pieces | Free | CC0 | PNG + Tiled template |
| [Kenney Isometric Blocks](https://kenney-assets.itch.io/isometric-blocks) | General isometric block/prop set, good filler | Free | CC0 | PNG |

**Vibe & reference:** Two Point Hospital's semi-isometric readability, Islanders' clean isometric
diorama look. The character-pack side of isometric is genuinely underserved right now — you'd
likely be recoloring a top-down or 3D-rendered-to-isometric character set rather than finding a
purpose-built isometric person pack.

---

## 5. Hand-drawn / illustrated / painterly

The honest state of this lane: it's the thinnest for cohesive, purpose-built game packs. What
turned up is scattered — individual furniture packs, VN-style character portraits — rather than a
matched room+character+UI set. Real options if this direction appeals:

| Pack | Covers | Price | License | Format |
|---|---|---|---|---|
| [shubibubi Cozy Interior](https://shubibubi.itch.io/cozy-interior) | Hand-drawn furniture set (kids' room palette — would need a broader theme sweep for office/hospital) | Check page | Own license | PNG |
| [POMPACK](https://pompack.itch.io/) | Illustrated character portraits/sprites, commercial-friendly | Varies | Own license | PNG |
| [ForsakenVoid 2D Hand-Drawn Player](https://forsakenvoid.itch.io/2d-hand-drawn-player) | Single hand-drawn character base, walk-cycle | Check page | Own license | PNG |

**The realistic path if you want this look specifically:** treat it as a commission or
custom-illustration project rather than an off-the-shelf shopping trip — there isn't a "buy this
one pack" answer here the way there is for the other four. **Reference:** *Unpacking*, *A Short
Hike*, *Behind the Frame* — warm painterly interiors, none of which shipped from a bought asset
pack either (they're bespoke).

---

## If you want to see them

Every storefront above has preview thumbnails; most itch.io pages have a scrollable image gallery
and several have short video previews. Worth 15 minutes clicking through, in this order for the
fastest visual read:
- **Synty POLYGON Office Pack** product page — has the richest gallery of the low-poly options.
- **RhosGFX Vector Furniture Pack** and **Vector Avatars** — itch.io pages show the full sprite
  sheet at a glance.
- **Netherzapdos Pixel Spaces** — itch.io page has a large scrollable asset-sheet preview and a
  gameplay-style GIF.
- **Project Highrise** on Steam — screenshots are the best single reference for "what does a
  vectorized SimTower actually look like in motion."

---

## Three shortlist directions worth prototyping

Not a ranking — three genuinely different bets, pick by feel:

1. **Flat vector** (RhosGFX Furniture + Avatars, ~$25-30) — cheapest, fastest, zero engine risk,
   works in Godot 4.2 today. Project Highrise is the mood-board proof this look suits an elevator
   sim specifically.
2. **Pixel art** (Netherzapdos Pixel Spaces, $15) — the only pack with elevators/doors/tiny-NPCs
   already matched as a set, and SimTower is literally this genre in this style. Biggest ask is
   the internal rework, not the art.
3. **Low-poly 3D dollhouse** (Synty POLYGON Office + City Characters, ~$80 to start) — the closest
   visual match to Fallout Shelter, now with a real Godot 4.5/4.6 project export from Synty
   directly. Needs the 4.3+ engine bump first, but that's a one-time, low-risk move per Godot's own
   migration notes.
