#!/usr/bin/env bash
# Parallel, leak-robust FI-MAP-Elites design EVOLUTION (island model).
#
#   usage: fievo_parallel.sh <rounds> <workers> <chunk> <expert_budget> <master.json> [workdir]
#
# Each round: seed every worker from the CURRENT master (island sync), evolve <chunk> new
# feasible designs each in parallel on separate project COPIES (short-lived processes dodge
# the GDScript CLI memory leak; separate copies dodge the import lock), then merge the
# islands back into the master by niche (best sweep / min violation-distance) via
# tools/merge_fievo.py. Unlike the seed-sampler, fievo's retype/add/remove/block mutations
# reach compositions and block layouts the generator's fixed wishlist never makes -- this is
# the search that actually FILLS the archive. Resumable + kill-safe (master whole per round).
set -u

ROUNDS="${1:?rounds}"; N="${2:?workers}"; CHUNK="${3:?chunk}"; EXPERT="${4:?expert_budget}"; MASTER="${5:?master.json}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${6:-$(dirname "$MASTER")/fievo_workers}"
GD="${GODOT:-/c/Program Files/Godot_v4.2.2-stable_mono_win64/Godot_v4.2.2-stable_mono_win64_console.exe}"

mkdir -p "$WORK"
echo "setting up $N worker copies under $WORK ..."
for k in $(seq 1 "$N"); do
  if [ ! -f "$WORK/w$k/project.godot" ]; then
    rm -rf "$WORK/w$k"; cp -r "$SRC" "$WORK/w$k"; rm -rf "$WORK/w$k/.git"
  fi
done

for r in $(seq 1 "$ROUNDS"); do
  echo "=== round $r/$ROUNDS : $N islands x $CHUNK evals (expert $EXPERT) ==="
  for k in $(seq 1 "$N"); do
    if [ -f "$MASTER" ]; then cp "$MASTER" "$WORK/part$k.json"; else rm -f "$WORK/part$k.json"; fi
    OFF=$(( r * 1000000 + k * 100000 ))
    ( cd "$WORK/w$k" && "$GD" --headless --path . --script tools/_pcg_gen.gd -- \
        fievo "$CHUNK" "$EXPERT" "$WORK/part$k.json" "$OFF" > "$WORK/w$k.log" 2>&1 )   &
  done
  wait
  python "$SRC/tools/merge_fievo.py" "$MASTER" "$WORK"/part*.json
done

echo "done. master archive: $MASTER"
