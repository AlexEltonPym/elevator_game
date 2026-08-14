# v5 suite rework — from playtest feedback

The first 14-level suite had too much filler/redundancy and some broken/samey levels. Rework
into a TIGHTER, more DIVERSE, more PURPOSEFUL set. Prioritise fun + geometry variety; the
classifier (tools/v5/run_depth5.gd) is triage only. Renumber per-world so IDs read sequentially
(the R-1,R-2,R-7,R-8 gaps in LEARN were confusing — global IDs shuffled across worlds).

## Cross-cutting
- **GEOMETRY DIVERSITY is the #1 note.** Too many levels are vertical single-shafts (docks face
  left/right, so shafts go vertical). Vary layouts: horizontal runs, L-shapes, branching,
  multi-shaft, rooms on both sides, the "cutaway building" feel. Not every level a column.
- **Cut redundancy.** Several levels are near-duplicates (see below). A tight suite of strong
  levels beats 14 with filler.

## Per-level verdicts (from the user)
- **R-1 One Lift** — good intro but wants geometry diversity; consider MERGING R-2 into it
  (one floor/route serving two rooms is the R-2 idea — fold it in as the natural 2nd beat).
- **R-2 Double Duty** — fold into R-1 / the early ramp rather than a standalone level.
- **R-7 Two Towers** — the "need a 2nd lift" isn't forced: the default open tiles let one lift
  do everything. Make the split REAL — either width-2 tiles between the towers or a BARRIER so a
  single lift can't cover both, so the 2nd lift is genuinely required.
- **R-8 The Narrows** — makes no sense: a one-at-a-time bottleneck with only ONE lift. R-5
  Bottleneck is the better version. CUT R-8 (or repurpose entirely).
- **R-5 Bottleneck** — good (corridor contention with two lifts). Keep.
- **R-6 Squeeze** — okay as the tight overlap puzzle, but needs better geometry diversity (it's a
  plain vertical cap-2 shaft). Reshape the geometry while keeping the cap-2-shaft + cap-4-transfer
  cooperation.
- **R-9 Relay** — GREAT, demonstrates the atrium/transfer well. Keep. (Transfer re-queue speed is
  being fixed separately.) This is the model for a good transfer level.
- **R-10 Threadneedle** — just R-6 with diversity; not a distinct puzzle. CUT or make genuinely
  different (a different overlap shape/constraint, not a reskinned Squeeze).
- **R-11 Express Run** — doesn't enforce good express use (express isn't clearly better). Give the
  express a SEPARATE CHANNEL: a layout where one side wants the express (a long clean run) and the
  other wants a normal/local (stop-heavy), so the lesson "put the express where the long haul is"
  is forced.
- **R-12 Freight** — BROKEN: the cargo car (width 3) can't fit through the width-2 corridor, so
  it's unwinnable. Redesign so cargo has a legal path (width-3 route/corridor for freight) and the
  width constraint is meaningful (cargo does the bulk/long freight run; the corridor is for the
  narrow cars). Verify cargo can actually complete its route.
- **R-3 Crossing** — just R-9 (another transfer). CUT or repurpose (it's currently the crowd-stress
  showcase with max_lost 400 — not a real level).
- **R-4 Big Store** — THE snake level. Make it teach the SNAKE mechanic: serve ALL of the store's
  doors/docks (and its service rooms) with the lifts WITHOUT the routes overlapping (overlap caps
  force non-overlapping snake routing). This is the "legal move tough, best move tougher"
  middleground the user wants — a real overlap-snake puzzle around a big multi-dock store.
- **R-13 Regulars** — boring. Reactivation/itineraries need to MATTER: a layout/demand where the
  return trips create a real routing decision, not just more of the same. Redesign or cut.
- **R-14 Interchange** — boring repeat. Cut or redesign into something distinct.

## Target shape (guidance, not rigid)
- **LEARN**: draw-a-route (+ one-route-two-rooms folded in), forced two-lift split (R-7 fixed),
  a gentle transfer, a gentle corridor. Renumbered sequentially.
- **MECHANICS**: R-5 corridor contention; R-9 transfer (keep); R-6 overlap puzzle (reshaped
  geometry); R-11 express with a separate channel; R-12 cargo (fixed, cargo path legal).
- **GENERIC / middleground**: R-4 as the store snake puzzle; one strong reactivation level; keep
  only distinct, non-repeating levels.
- Net: fewer, more diverse, more purposeful levels. Cut R-8, R-10, R-3, R-14 unless a genuinely
  distinct redesign is found; fold R-2 into R-1.

## Verify
Each surviving/new level winnable by a hand solution (scripted for smoke/fingerprint); geometry
varied; run_depth5 triage shows no BROKEN and the intended puzzle/soft split; det=Y; record the
new fingerprint5 baseline (existing kept levels' per-scenario hashes stay identical where the
level is unchanged).
