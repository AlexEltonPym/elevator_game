# Prototype v2 spec — "Network Planner"

Direction A from [game-design.md](game-design.md), incorporating the critique's fixes.
Chill strategy pacing (Mini Motorways / tower-defense planning vibes), NOT fast action.
Player designs the elevator network; cars run themselves on dumb-but-legible AI.

## Core rules

### Building
- 10 floors (0 = LOBBY, 7 = SURGERY, others W1..W8 wards), fixed for the whole campaign.
- 4 fixed shaft columns. A column is empty until the player installs an elevator card in it.
- **Transfer floors** (per level data): floors where passengers may exit one shaft and walk
  to another to continue their journey. Drawn as a highlighted "bridge" band across the
  building. On non-transfer floors passengers only board (at origin) or alight (at destination).

### Elevator cards (inventory / deckbuilder)
- Inventory panel at the bottom of the screen holds unplaced cards.
- Tap a card to select it → empty columns glow → tap a column to install. Tap an installed
  car/column header to select it → "Remove" button returns it to inventory (free undo).
- Card types:
  | card     | capacity (slots) | speed  | look                |
  |----------|------------------|--------|---------------------|
  | standard | 4                | 300 px/s | gray-blue rect    |
  | large    | 8                | 210 px/s | wide rect         |
  | express  | 4                | 540 px/s | accent color, chevrons |
- Starting inventory: 2× standard. Rewards add more (see levels).

### Doors-per-floor (the expressive language)
- A newly installed elevator serves ALL floors (all doors ON).
- With an elevator selected, tap any floor cell in its column to toggle that door ON/OFF.
  Minimum 2 doors ON. An "express to surgery" emerges from toggling everything else off.
- Editing is allowed at any time, including while paused.

### Passenger journey & transfers
- On spawn, a passenger computes a path: an ordered list of legs (elevator, board floor,
  alight floor). BFS over the network: elevator E gives an edge between any two floors whose
  doors are ON; an intermediate alight is only legal on a transfer floor. Minimize leg count,
  tie-break by rough travel distance.
- No path? Passenger waits showing a "?" bubble; patience still drains. Recompute all
  waiting passengers' paths whenever the network changes (install/remove/toggle).
- Riders finish their current leg, then recompute if needed.
- Patience drains ONLY while waiting/queued (not while riding). Empty patience → passenger
  leaves, Lost +1.

### Elevator AI (sweep, legible)
- Car sweeps in its current direction, stopping at door-ON floors where a rider wants to
  alight or a waiter's current leg names this elevator. No stops in that direction → reverse.
  Nothing to do at all → idle in place. Dwell ~1.2 s at stops; unload then load (slot-aware).

### Passenger types
| type      | slots | patience | visuals            | notes |
|-----------|-------|----------|--------------------|-------|
| visitor   | 1     | 90 s     | green circle       | |
| patient   | 1     | 75 s     | blue circle        | |
| gurney    | 2     | 60 s     | wide orange rect   | from H-2 |
| emergency | 1     | 30 s     | red, pulsing       | from H-3; destination is ALWAYS floor 7 (SURGERY) |
- Destinations otherwise: 60% of trips involve the lobby (either direction), 40% ward↔ward.

### Pacing / chill controls
- Speed buttons: ⏸ pause / 1× / 3×. Building is editable in every state.
- Spawn intervals are slow (see levels); patience is generous. The pressure is strategic
  (is my network shaped right?), not twitch.

## Campaign: Hospital H-1 → H-3

Win a level by serving its quota before losing `max_lost` passengers. Network, door
settings, and inventory PERSIST between levels (the "hope you set yourself up in H-1" hook).
Lose → retry same level, network intact, counters reset.

| level | quota | max_lost | spawn every | mix                                          | transfer floors | intro text hook |
|-------|-------|----------|-------------|----------------------------------------------|-----------------|-----------------|
| H-1   | 15    | 5        | 6.0 s       | visitor .4 / patient .6                      | 0, 5            | learn placement & doors |
| H-2   | 25    | 5        | 4.5 s       | visitor .3 / patient .5 / gurney .2          | 0, 5            | gurneys take 2 slots |
| H-3   | 35    | 5        | 4.0 s       | visitor .25 / patient .45 / gurney .15 / emergency .15 | 0, 5, 7 | emergency surgeries — 30 s patience to SURGERY |

- Reward after H-1: choose 1 of [large, express]. After H-2: choose 1 of [express, standard]
  (the un-picked H-1 card reappears as an option if applicable — keep it simple: offer the
  two listed; duplicates allowed).
- After H-3: campaign-complete overlay with total stats + restart.
- Level intro overlay before each level: level id ("H-2"), one line of flavor, what's new,
  Start button. Time does not run during overlays.

## Screen layout (portrait 720×1280, one-thumb)
- Top HUD (~90 px): level id, Served n/quota, Lost n/max, speed buttons.
- Building cutout (~950 px): floor labels left (LOBBY/W1../SURGERY), 4 columns, transfer
  bridges highlighted, queues render beside columns.
- Bottom panel (~220 px): inventory cards + contextual actions (Remove when a car is
  selected). All tap targets ≥ 90 px.
- Same project settings as v1: canvas_items stretch, expand aspect, emulate_touch_from_mouse.

## Out of scope for this prototype
Sound, art assets, tenant-event demand drip (next experiment after this), score/stars,
more themes. Keep programmer art.
