# Generic / tutorial levels — a ramped campaign

Thesis levels (L-, W-series) are proving grounds: they demand a big skill gap (random-win
≤5%, naive LOSES, thesis WINS). That makes them bad tutorials and bad generic content — a
tutorial you can only win with the one right idea isn't teaching, it's testing. This spec adds
a **new class of level** with the OPPOSITE early bar: forgiving, one-concept-at-a-time, ramping.

## The key idea: random-win-rate IS the difficulty ramp

We already measure the share of uniformly-random route-sets that win a level (`--scorecheck`).
- Thesis levels drive it to **≤5%** (only the right plan wins).
- A good tutorial curve is the SAME number **descending**: G-1 near-unloseable (~90%+), each
  level tightening, the last approaching the thesis floor.

So "difficulty ramps monotonically" becomes a verifiable assertion: the measured random-win-rate
is **non-increasing** across G-1…G-N, G-1 is very forgiving, and G-N approaches thesis rigor.

## Level class tag

Add a `class` field to each level: `"thesis"` (existing L/W/X, strict axioms) or `"generic"`
(these). The balance suite branches on it:
- **generic** levels assert: intended/thesis plan **WINS ≥ 15/16** `SEEDS_ASSERT` (a tutorial
  must still be winnable — this is the one hard requirement), the measured random-win-rate falls
  in the level's declared `winband` [lo,hi], and every room has demand.
- **generic** levels do NOT assert "naive LOSES" and do NOT require a skill gap. A ~0 gap between
  a novice plan and an optimizer is EXPECTED and fine for the early ones — say so, don't fail it.
- A suite-level assertion checks the whole generic ramp is **monotonically non-increasing** in
  random-win-rate (small tolerance allowed for measurement noise; report the curve).

## The curriculum (G-1 … G-7), each introduces ONE concept

Geometry/demand are the builder's to design to hit the band; keep them small and legible — these
are the player's first contact with each idea. `winband` is the target random-win-rate range.

| id  | name          | concept introduced                    | cards                 | winband (random-win) |
|-----|---------------|---------------------------------------|-----------------------|----------------------|
| G-1 | First Lift    | draw a route through rooms, press RUN | 1 standard            | 85–100 % (near-unloseable) |
| G-2 | Full Line     | one car serves a whole column/line    | 1 standard            | 65–90 % |
| G-3 | Second Shaft  | two cars cover more; split the work   | 2 standard            | 45–70 % |
| G-4 | Interchange   | transfers: ride to a shared stop, switch | 2 standard + express | 30–55 % |
| G-5 | One at a Time | a gate corridor queues cars           | 2 standard (+gate)    | 20–45 % |
| G-6 | Pods & Freight| width: pods, cargo, a narrow corridor | pod + standard + cargo| 12–35 % |
| G-7 | Express Lane  | acceleration: express wins long runs  | pod + standard + express | 5–20 % (bridges to thesis) |

Rules for the ramp:
- Each level's concept is NEW vs the previous; earlier concepts may recur but the level should be
  winnable without mastering them.
- The intended "thesis" route-set is the clean demonstration of the concept and must win 16/16.
- Provide a "naive"/beginner route-set too (for watch mode and as the honest first-try). For the
  EARLY levels it will also usually WIN — that's the point, and it's not a failure.
- Introduce mechanics gently: G-5's gate should rarely bite at this demand; G-6's width constraint
  should be obvious (e.g. one cargo passenger that only the cargo car fits) not subtle; G-7's
  express advantage should be feelable but the level still winnable with plain cars.
- Patience generous early, tightening slightly along the ramp. Prefer forgiving demand over
  frame-perfect timing.

## Level select

Add a new world **LEARN** (or "CAMPAIGN") as the FIRST world (what a new player sees), holding
G-1…G-7 in order. The existing PATH and WIDTH thesis worlds move after it. Keep the paging/UI
from the recent UI pass; the LEARN world has 7 levels (fits with the grid-fit scaling already in).

## Verification pipeline

Same tools, generic-aware:
- `tests/run_balance.gd`: generic assertions above (winnable + winband + monotonic ramp), thesis
  assertions unchanged for L/W/X. Multi-seed on `SEEDS_ASSERT`; tune on `SEEDS_TUNE`.
- `tools/run_depth.gd --scorecheck`: report each generic level's random-win-rate; confirm the
  ramp. The `--tune`/`--lengthsweep` modes should still work.
- Regenerate `docs/depth-report.md` (it will now include the generic levels; mark their class so
  their low skill_gap reads as intended, not as a shallow-level warning) and `discovered3.gd`.
- Watch mode (NAIVE/THESIS/BEST) works for the generic levels too.

## Acceptance
- All 7 generic levels: intended plan WINS ≥15/16 held-out seeds; measured random-win in band;
  the G-1…G-7 random-win curve is monotonically non-increasing (report it).
- Existing L/W/X thesis axioms still 16/16, unchanged.
- Fingerprint will change (new levels add scenarios); the existing levels' per-scenario
  fingerprints stay byte-identical (prove the generic levels are purely additive).
- `--smoke` ALL PASS; game launches; LEARN world is first and all its levels PLAY + watch.

## Honesty
- Report the actual random-win curve; if a level can't hit its band without feeling unfair or
  breaking winnability, widen the band and say why rather than forcing it.
- A generic level with ~0 skill gap is working as intended; the report should frame it that way,
  not as a defect. The thesis levels remain the place we demand depth.
