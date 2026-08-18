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

3. **Rooms are non-standard shapes placed as ISLANDS, anywhere.** Use tetris-ish shapes
   (L / T / plus / 2×2 and larger). **A 2×1 room reads as a normal room — avoid it.**
   Rooms are islands the routes weave *around*; they are **not required on the outer
   edge**, and the layout is **not** a central shaft with rooms lining the walls. Prefer
   an open field with a few rooms in the interior. Fewer, bigger rooms > many small ones.

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
