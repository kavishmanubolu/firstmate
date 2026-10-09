#!/usr/bin/env bash
# Live drive: real bin/fm-watch-arm.sh in a disposable lab home.
set -u
W=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$W/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux"
export TMUX_TMPDIR="$LAB/tmux"; unset TMUX NO_MISTAKES_GATE FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
export FM_HOME="$LAB" FM_POLL=1 FM_SIGNAL_GRACE=0 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 FM_ARM_CONFIRM_TIMEOUT=20
S=$LAB/state; REC=$LAB/left-record
lockpid() { cat "$S/.watch.lock/pid" 2>/dev/null; }
waitnew() { local old=$1 p i; for i in $(seq 1 300); do p=$(lockpid); [ -n "$p" ] && [ "$p" != "$old" ] && kill -0 "$p" 2>/dev/null && { echo "$p"; return 0; }; sleep 0.1; done; return 1; }
echo "== lab home: $LAB"
# Start the arm 19 re-arms in, so one more re-arm hits the 20 cap.
FM_WATCH_PREDECESSOR_ARM_PID=$$ FM_WATCH_ARM_LEFT_REARMS=19 FM_WATCH_ARM_LEFT_RECORD="$REC" "$W/bin/fm-watch-arm.sh" > "$LAB/arm.out" 2>&1 &
ARM=$!
W1=$(waitnew none) || { echo "no watcher"; cat "$LAB/arm.out"; exit 1; }
printf '%s\tlab-identity\n' "$ARM" > "$REC"
echo "== left arm pid=$ARM, watcher W1=$W1 (ppid $(ps -o ppid= -p "$W1" | tr -d ' '))"
"$W/bin/fm-watch-arm.sh" > "$LAB/attach.out" 2>&1 &
ATT=$!
sleep 3
echo "== attached plain arm pid=$ATT output so far:"; sed 's/^/   /' "$LAB/attach.out"
echo "== close 1: write a status change"
printf 'done: lab close one\n' > "$S/demo.status"
W2=$(waitnew "$W1") || echo "!! no new watcher after close 1"
echo "== after close 1: lock holder W2=$W2 ppid=$(ps -o ppid= -p "$W2" | tr -d ' ') ; left arm alive: $(kill -0 $ARM 2>/dev/null && echo yes || echo no)"
for i in $(seq 1 100); do kill -0 $ATT 2>/dev/null || break; sleep 0.1; done
wait $ATT; echo "== attached arm exit=$? output:"; sed 's/^/   /' "$LAB/attach.out"
echo "== left arm output:"; sed 's/^/   /' "$LAB/arm.out"
echo "== wake queue:"; sed 's/^/   /' "$S/.wake-queue" 2>/dev/null
echo "== close 2 (re-arm count now 20 = cap): status change"
printf 'done: lab close two\n' >> "$S/demo.status"
for i in $(seq 1 300); do kill -0 $ARM 2>/dev/null || break; sleep 0.1; done
if kill -0 $ARM 2>/dev/null; then echo "!! left arm still alive past the cap"; else wait $ARM; echo "== left arm ended at the cap, exit=$?"; fi
echo "== cycle exit ledger tail:"; tail -6 "$S/.watch-cycle-exits.log" 2>/dev/null | sed 's/^/   /'
for p in $(lockpid) $ARM $ATT; do kill $p 2>/dev/null; done; sleep 1
rm -rf "$LAB"; echo "== lab removed: $( [ -e "$LAB" ] && echo no || echo yes)"
