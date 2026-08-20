#!/usr/bin/env bash
# Parallel, leak-robust MAP-Elites design sweep.
#
#   usage: pcg_parallel.sh <rounds> <workers> <chunk> <expert_budget> <master.json> [workdir]
#
# WHY: a single long-running Godot --script process leaks memory (GDScript CLI leak
# godotengine/godot#68009) and gets OOM-killed in the background after a few evals. This
# runs each chunk as a SHORT-LIVED process (memory reclaimed on exit) and fans <workers>
# of them out across CPU cores on separate project COPIES (same-project instances collide
# on the import lock). Each round: <workers> x <chunk> designs in parallel, then a pure-
# Python merge folds the partials into <master.json> (best design per niche). Resumable:
# re-run to add more rounds; the master accumulates. Kill any time -- the master is whole
# after each round.
set -u

ROUNDS="${1:?rounds}"; N="${2:?workers}"; CHUNK="${3:?chunk}"; EXPERT="${4:?expert_budget}"; MASTER="${5:?master.json}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"           # repo root (tools/..)
WORK="${6:-$(dirname "$MASTER")/pcg_workers}"
GD="${GODOT:-/c/Program Files/Godot_v4.2.2-stable_mono_win64/Godot_v4.2.2-stable_mono_win64_console.exe}"

mkdir -p "$WORK"
echo "setting up $N worker copies under $WORK ..."
for k in $(seq 1 "$N"); do
  if [ ! -f "$WORK/w$k/project.godot" ]; then
    rm -rf "$WORK/w$k"
    cp -r "$SRC" "$WORK/w$k"
    rm -rf "$WORK/w$k/.git"
  fi
done

for r in $(seq 1 "$ROUNDS"); do
  echo "=== round $r/$ROUNDS : $N workers x $CHUNK evals (expert $EXPERT) ==="
  rm -f "$WORK"/part*.json   # each round's workers start FRESH (they don't resume partials)
  for k in $(seq 1 "$N"); do
    OFF=$(( r * 1000000 + k * 100000 ))
    ( cd "$WORK/w$k" && "$GD" --headless --path . --script tools/_pcg_gen.gd -- \
        mapgen "$CHUNK" "$EXPERT" "$WORK/part$k.json" "$OFF" > "$WORK/w$k.log" 2>&1 )   &
  done
  wait
  python "$SRC/tools/merge_mapgen.py" "$MASTER" "$WORK"/part*.json
done

echo "done. master archive: $MASTER"
