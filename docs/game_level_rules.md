# Game / Level Design Rules — READ BEFORE BUILDING ANY LEVEL

Authoritative, user-set constraints. These are decisions the user has made and does not
want re-litigated or re-forgotten. **Check this list before designing or editing a level.**
If a rule here seems wrong for a task, ask — do not silently violate it.

## Hard layout constraints (most-often-violated — check these first)

1. **No scrolling, no growing the grid to fit more.** The playfield is a fixed, small,
   fully-visible board. The user spent real time tuning the sizing (`CELL=90`, the
   `Grid5` fit transform) and does not want it shrunk to cram in a taller/bigger level.
   Keep the grid small enough to stay readable — roughly **cols ≤ 9, rows ≤ 13**, and the
   fit `view_scale` should stay ≳0.7. A 20+ row tower (scale ~0.45) is a FAIL.

2. **All dropoffs are HORIZONTAL.** Every room drop uses dir `L` or `R` (dock = the open
   cell left/right of a room cell). **No vertical (`U`/`D`) dropoffs** — "they just make
   no sense, for now." Dropoffs are orthogonal to a *side* of a room.

2b. **One dropoff per room** by default; only a few hub rooms (atrium, cafe) get 2.
   Don't sprinkle 3+ docks on ordinary rooms. A room served by multiple lifts uses ONE
   **shared** dock (cap-6), not one dock per lift.

2c. **No dock directly above/below another room cell.** A dock vertically adjacent to a
   room reads as serving that room via verticality — not allowed. One dock serving TWO
   rooms is fine *only when both rooms are horizontally adjacent to it* (left + right).

2d. **A dock sandwiched between two rooms must INTENTIONALLY serve both.** If a dock has a
   room on its left AND a room on its right, it reads as serving both — so it must actually
   connect to both (both rooms drop to it: a deliberate shared/transfer dock, allowed). If
   a dock should serve only ONE room, do NOT sandwich it — leave the cell on its other side
   open. Never leave an ambiguous dock that touches two rooms but only serves one.

3. **Rooms are non-standard shapes placed as ISLANDS, anywhere.** Use the shape catalogue
   below. Rooms are islands the routes weave *around*; they are **not required on the outer
   edge** (except the entry rooms, rule 3b), and the layout is **not** a central shaft with
   rooms lining the walls. Prefer an open field with a few rooms in the interior. Fewer,
   bigger rooms > many small ones.

   **Shape catalogue (user-drawn 2026-08-19; all horizontally flippable):**
   lobby = 3×2; delivery = 2×2; apartment = 2×1; penthouse = 4 bottom + 2 top (symmetric,
   couch bottom-left mirrored by a block bottom-right); cafe = 4 top + 2 bottom with its
   two docks tucked into the bottom notch. Other room
   types get their own shapes in this spirit — bigger than 2×1 except apartment, distinct
   silhouettes. A dock tucked in a room's OWN concavity (same room above/below) is fine;
   only a dock under a DIFFERENT room is banned (rule 2c).

3b. **People-entry rooms touch the bottom edge, in the corners.** Rooms where PEOPLE enter
   the building **from outside the screen** (off the bottom of the map) — always the lobby,
   and any similar people-entrance — sit in the bottom corners (lobby = bottom-left). Flip a
   corner room horizontally so its dock faces inward. An internal room (e.g. a STORAGE /
   cargo bay for goods, not people) does NOT need to touch the bottom and can sit in the
   interior. (Rooms can carry a `label` field to show custom background text while keeping
   their type/theme — e.g. a "delivery"-typed room labelled STORAGE.)

4. **Tall rooms = one extra-tall space, never stacked floors.** A tall room is a single
   volume (skylight at the top), not sliced into floors by internal borders. A ladder
   marks interior-vertical stretches so it reads as traversable.

5. **Scale everything uniformly** (native art ratios via `ART_K`) — furniture, people,
   doors all scale together with the grid. Don't special-case sizes.

6. **Furniture:** inset (never overlapping the room's edge/walls), may span tiles, placed
   on the floor row, positioned **opposite the dropoff door**.

7. **People stand on the floor** (grounded), not floating.

## Visual language

- **Each room TYPE has a unique background colour + theme.** Once you learn a room, you
  know how it behaves. Shapes may vary but the colour is authoritative. (Current temporary
  aid: a faint background TYPE label is drawn in each room — this is scaffolding; the goal
  is furniture + shape + colour carrying identity, then the label goes.)
- **Levels self-explain: NO intro / briefing text.** Selecting a level lands straight in
  PLAN. Teach through layout, gameplay, narrative, and art — not a text dump.

## Routing / overlap conventions (current "numberlink / snake-fitting" direction)

- **Disjoint by default.** Open cells cap at **3**: two width-2 lifts (LOCAL/EXPRESS) can't
  share a cell (2+2 > 3), so their routes are disjoint snakes; a width-3 CARGO exactly fits.
- **Dropoffs may be shared.** Dock cells cap at **6** so multiple routes may share a
  dropoff (softer disjointness). A room served by several lifts still needs enough docks.
- **Overlap viz:** disjoint tiles render **blank** (the default); only **shareable** tiles
  (cap ≥ 4) get the subtle blue tint + capacity pips. Don't amber-outline the whole board.
- The magnetic route-drawing verb is sacred — preserve it exactly.

## Design intent (what the puzzles are FOR)

- **The fun is open-ended snake-fitting, not one optimal answer.** Softness (many viable
  routes) is a FEATURE. Do NOT railroad a single provably-optimal solution.
- **The wiggly express** (weaving/bypass) is the interesting drawing verb. Numberlink
  connections emerge from demand (e.g. cargo must reach the cafe, so it cuts across and
  everything routes around); the fast EXPRESS naturally takes the long way.
- **Momentum finding (settled):** demand-shaping alone can't make an express-skip the
  global optimum (a serve-all loop + coverage-split ties it) — see
  [momentum-skip-express memory]. It only matters with obstacles/travel-cost. So don't
  rely on it as the puzzle's crux; use it as flavour on top of the routing puzzle.

## Process / verification (engineering rules)

- **Fingerprint discipline.** `FINGERPRINT5-ALL 795467658` must stay byte-identical for any
  RENDERING-only change (verify with `tools/v5/run_fingerprint5.gd`). A SIM change
  legitimately rebaselines it — flag that explicitly and keep `V5 SMOKE ALL PASS`.
- **Parse-check headless first** (`godot --headless ... scenes/v5_main.tscn --quit-after N`)
  before the windowed run — a parse error makes the windowed scene hang silently.
- **Commit + push often**, directly to `main`, only after verifying green.
- Level demos are injected via `Levels5.injected` (throwaway `tools/_shoot_*.gd`); they
  don't touch the shipped `LEVELS` table or the fingerprint until promoted deliberately.
