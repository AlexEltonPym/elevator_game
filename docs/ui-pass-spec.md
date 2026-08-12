# UI pass — level select, briefing, in-level declutter

Three problems, from real screenshots at 720x1280. This is a PRESENTATION pass only:
it must not change simulation behaviour. `tools/run_fingerprint.gd` must print the same
`FINGERPRINT-ALL 2693288479 len=38734` before and after — prove it.

## 1. Level select — it overflows and doesn't scroll

Current: a CenterContainer of 8 rows, each a 470px PLAY button + a 150px WATCH column.
Eight rows are taller than the screen (no scroll) and the WATCH column clips off the right edge.

Redesign as **paged worlds** ("superlevels"):
- Define worlds explicitly in `Levels3` (a small table, not id-prefix guessing), each a title +
  its level ids:
  - **PATH** — L1, L2, L3, L4, X-1
  - **WIDTH** — W-1, W-2, W-3
- Show ONE world at a time. A header row with big left/right arrow buttons (>=90px tap targets)
  and the world name + position ("PATH  1/2"). Arrows wrap or clamp — your call, but both arrows
  must be visibly disabled/hidden at the ends if they clamp.
- Each world's levels fit on ONE screen with no scroll (max 5 today). If a future world exceeds
  what fits, fall back to a ScrollContainer for that world — but the arrow paging is the primary
  navigation.
- **Row layout, must fit within 720 wide with margins:** the level card is the full-width primary
  PLAY target (id + name + one-line thesis), height ~110-120. WATCH is secondary and must not eat
  horizontal space: put a single compact strip UNDER the card with three small buttons labelled
  **N / T / B** (naive / thesis / best), each >=90px wide and tall enough to tap, tinted as today
  (red/green/blue). Only show B where `Discovered3.has(id)`; only show N/T where the scenario set
  has them. A tiny legend once at the bottom ("N naive · T thesis · B best") so the letters read.
- Nothing horizontal may exceed the viewport. Verify by measuring real post-layout rects.

## 2. Briefing — cut the wall of text

Current `Levels3.briefing_body` dumps: thesis quote, a multi-paragraph `intro`, verbose YOUR
ELEVATORS lines, verbose WHO SHOWS UP lines, a pace sentence, GOAL. Screenshot shows ~25 lines.
It must be scannable in a couple of seconds.

- **Drop the `intro` flavour paragraph from the briefing entirely.** (Keep the field in the data;
  just stop rendering it here. If you want it reachable, a small "?" toggle may reveal it, but the
  default briefing must not show it.)
- **Compact the roster** to one terse line per car: `NAME · type · wN · C slots · <speed/ramp only
  if non-default>`. Drop "steady ramp" and "normal (1.0x)" — only surface a trait when it differs
  from standard (e.g. "fast", "sluggish", "sharp"). Example target: `EXPRESS · express · w2 · 4 ·
  fast`.
- **Compact WHO SHOWS UP**: one terse line per type: `visitor 43% · w1 · 72s`. Fold the exec/
  freight room routing into a short tail only when present: `exec 15% · w1 · 44s · B/F→G`.
- Keep the pace line but shorten: `Bursts of 4-6, every 0.9s→0.6s`.
- Keep GOAL as one line.
- Result target: title + one-line thesis + ~3 roster lines + ~3 people lines + pace + goal +
  PLAN. Roughly 10-12 lines, no paragraph.
- Provide compact variants as new functions (e.g. `roster_line_short`, `people_line_short`) so the
  balance-suite briefing lint can still check the essential facts appear; keep the verbose ones if
  anything else uses them, else remove.

## 3. In-level — declutter chips and the maze art

### Chips (bottom panel)
Current chip is 4 lines: name / `type - wN, C slots` / `N cells - M stops` / `needs 2 stops!` or
home. Too dense.
- Reduce to **2 lines**: line 1 = card NAME; line 2 = terse spec `type · wN · C` (e.g.
  `standard · w2 · 6`). 
- Route state moves off the text: show a small **state pip** on the chip — grey = no route,
  amber = drawn but <2 stops (invalid), green = valid; a small house glyph when a home is set.
  The "needs 2 stops" wording already lives on the hint line, so it need not be on the chip.
- Keep the selected-chip white border. Keep chips disabled outside PLAN.

### Maze programmer art (grid.gd _draw)
The maze currently competes with the route lines and cars for attention (heavy diagonal hatching
on every blocked cell, a loud bright-yellow dashed gate band, door ticks). The maze should RECEDE
so routes, cars, gates-as-meaningful and passengers read first.
- **Blocked cells:** replace the busy diagonal hatch with a flat, slightly-darker-than-background
  fill and a thin subtle border (or a very low-contrast texture). They should read as "not here"
  at a glance, not as active content.
- **Open/room cells:** keep rooms clearly legible (letter + a calm fill); make plain open shaft
  cells quiet.
- **Gate corridors:** keep the hazard identity but calmer — a thinner striped border, not a
  full bright band; the occupied-tint (holder colour) stays since it's meaningful.
- **Door markers:** lighter / smaller; they matter less than the route line.
- Do NOT touch the dynamic layer that must stay loud: route polylines, drag preview, direction
  chevrons, car bodies/pips, gate occupancy tint, passenger figures, the redeploy ghost. Those are
  the foreground; only the static maze recedes.
- Keep everything readable at phone size and in the existing palette; this is a contrast/weight
  rebalance, not a recolour.

## Validation
- Fingerprint identical (`2693288479 len=38734`) — presentation only.
- `tests/run_balance.gd` ALL PASS (146), including the briefing lint against the new compact text.
- `--smoke` ALL PASS: select builds and pages between worlds; every level PLAYs through
  BRIEFING->PLAN->RUN; WATCH N/T/B all launch.
- Measure real post-layout geometry: nothing exceeds 720 wide; level-select and briefing both fit
  720x1280; all tap targets >=90px. Paste the measured worst-case rects.
- Since I can't screenshot the desktop app from here, describe each screen's final layout
  precisely in the report so the result can be checked against a screenshot.
