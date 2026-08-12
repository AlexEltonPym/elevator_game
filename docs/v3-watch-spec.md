# v3.2 — gate corridors, naive-must-lose retune, v2 removal, in-game watch mode

Four changes, in dependency order.

## 1. Gate corridors (longer one-at-a-time sections)

- Orthogonally contiguous `G` cells now form ONE gate group = ONE mutex. A car acquires
  the whole group before entering its first cell and releases only after fully exiting to
  a cell outside the group. FIFO per group, as before. Single isolated `G` cells behave
  exactly as today (group of 1) — X-1's three gates must be byte-for-byte unchanged in feel.
- Visuals: stripe the full corridor; while held, tint the whole group faintly with the
  holder's color so "the tunnel is occupied" reads at a glance; queued cars keep the
  pulsing outline.
- Redesign L2 so the short path's gate is a 3-4 cell corridor (transit ≥ ~1.2 s at
  standard speed, longer with stops nearby). This is what makes queues VISIBLE and gives
  the level teeth.

## 2. Retune: naive must LOSE everywhere

> **SUPERSEDED, v3.5 level pass.** The last line below — "assertions only bind on the
> canonical seed" — was the bug. A one-seed axiom measures seed luck: when the depth
> tools held these claims out on 8 unseen seeds, L3's naive strategy won 6 of them. The
> suite now asserts `thesis WINS >= 15/16` and `naive LOSES >= 15/16` over 16 HELD-OUT
> seeds (`Scenarios3.SEEDS_ASSERT`), tuned against a disjoint 16 (`SEEDS_TUNE`), and
> prints the per-seed split. Everything else in this section still stands, including
> "the naive scenarios themselves must stay HONEST".


New harness assertions (replace the old per-level ones; keep the stats table):
- L1, L2, L3: naive scenario LOSES (hits max_lost before quota). Intended scenario WINS
  with lost ≤ 3.
- L2 additionally: naive gate wait ≥ 3× intended (the corridor should make this easy).
- L3 additionally: arm→penthouse 2-leg share ≥ 40% in intended (unchanged).
- X-1 smoke: unchanged (winnable by old strategy).
Tune level demand (spawn/patience/quota — not assertions) until all pass. The naive
scenarios themselves must stay HONEST — the plausible thing a new player tries, not a
strawman (do not degrade naive routes to make them fail; make the demand punish the
strategy). Keep intended wins comfortable, not knife-edge: intended should also pass with
a couple of alternate seeds (spot-check ≥2 other seeds; assertions only bind on the
canonical seed).

## 3. Remove v2 entirely

- Delete v2 scripts (top-level scripts/building.gd, elevator.gd, hud.gd, levels.gd,
  main.gd, passenger.gd, pathfind.gd), scenes/main.tscn, and the boot menu
  (scenes/menu.tscn, scripts/menu.gd).
- Project main scene becomes the v3 level select. The in-game MENU button now returns to
  level select (rename its label accordingly, e.g. LEVELS).
- README: drop all v2/menu sections; docs/v2-spec.md stays in the repo as history.
- After deletion: refresh the global class cache (--headless --editor --quit) and verify
  zero dangling references (headless load of every remaining scene).

## 4. In-game watch mode (visual naive-vs-thesis comparison)

- The scenario route sets move to shared game data (e.g. scripts/v3/scenarios3.gd with
  per-level {naive: [cells...], thesis: [cells...]}); tests/ imports from there so the
  harness and the game can never drift apart.
- Level select: each level row gets three actions — PLAY, plus WATCH NAIVE and
  WATCH THESIS.
- Watch mode = the normal level scene with: the scenario's routes pre-drawn, route
  editing DISABLED (taps on the grid do nothing; card chips display-only), a banner
  ("WATCHING: NAIVE" / "WATCHING: THESIS" in the strategy's tone), speed controls active
  (default 1×; user may 3× or pause), and an EXIT button back to level select.
- Watch runs use the harness's canonical fixed seed so NAIVE and THESIS face the
  identical demand sequence — that's what makes the comparison fair and repeatable.
  Normal PLAY stays unseeded.
- Win/lose overlays still appear (showing the strategy's result) with Watch Again /
  Level Select.

## Validation gates
- Balance harness: ALL PASS under the new assertions (paste table).
- Headless clean load: level select (new main scene), every level via PLAY, and every
  watch scenario (instantiate each level in watch mode for both strategies, tick a few
  simulated minutes, no errors).
- grep-level check that nothing references the deleted v2 files.
