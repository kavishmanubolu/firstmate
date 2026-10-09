#!/usr/bin/env bash
# Live drive (adversarial guards): real bin/fm-watch-arm.sh / fm-watch.sh in a disposable lab home.
set -u
W=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$W/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux"
export TMUX_TMPDIR="$LAB/tmux"; unset TMUX NO_MISTAKES_GATE FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
export FM_HOME="$LAB" FM_POLL=1 FM_SIGNAL_GRACE=0 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 FM_ARM_CONFIRM_TIMEOUT=20
S=$LAB/state
lockpid() { cat "$S/.watch.lock/pid" 2>/dev/null; }
waitnew() { local old=$1 p i; for i in $(seq 1 300); do p=$(lockpid); [ -n "$p" ] && [ "$p" != "$old" ] && kill -0 "$p" 2>/dev/null && { echo "$p"; return 0; }; sleep 0.1; done; return 1; }
echo "== lab home: $LAB"
echo "== A) record names a different pid: the arm must end at its close, not re-arm"
printf '999999\tnot-this-arm\n' > "$LAB/rec"
FM_WATCH_PREDECESSOR_ARM_PID=$$ FM_WATCH_ARM_LEFT_RECORD="$LAB/rec" "$W/bin/fm-watch-arm.sh" > "$LAB/a.out" 2>&1 &
A=$!; WA=$(waitnew none) || { echo no watcher; cat "$LAB/a.out"; }
printf 'done: close A\n' > "$S/demo.status"
for i in $(seq 1 300); do kill -0 $A 2>/dev/null || break; sleep 0.1; done
if kill -0 $A 2>/dev/null; then echo "!! arm still alive (re-armed without a matching record)"; kill $A; else wait $A; echo "   arm ended, exit=$?"; fi
sed 's/^/   /' "$LAB/a.out"
sleep 1; P=$(lockpid); if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then echo "   lock holder still alive: $P (ppid $(ps -o ppid= -p $P|tr -d ' '))"; kill $P; else echo "   no live watcher left behind"; fi
sleep 1
echo "== B) non-arm parent (bash loop standing in for the daemon) starts watchers back to back; a plain arm attached must FOLLOW, not report"
bash -c 'while [ ! -e "$2/stop-loop" ]; do "$1/bin/fm-watch.sh" >> "$2/loop.out" 2>&1; done' _ "$W" "$LAB" &
LOOP=$!
D1=$(waitnew none) || echo "!! loop watcher never started"
echo "   loop pid=$LOOP watcher D1=$D1 ppid=$(ps -o ppid= -p "$D1"|tr -d ' ')"
"$W/bin/fm-watch-arm.sh" > "$LAB/b.out" 2>&1 &
B=$!; sleep 4
printf 'done: close B\n' >> "$S/demo.status"
D2=$(waitnew "$D1") || echo "!! no D2"
echo "   after close: D2=$D2 ppid=$(ps -o ppid= -p "$D2" 2>/dev/null|tr -d ' ')"
sleep 6
if kill -0 $B 2>/dev/null; then echo "   attached arm still following (alive) - expected"; else wait $B; echo "!! attached arm exited=$?"; fi
echo "   attached arm output:"; sed 's/^/   /' "$LAB/b.out"
: > "$LAB/stop-loop"; kill $B 2>/dev/null; for p in $(lockpid); do kill $p 2>/dev/null; done; sleep 1; kill $LOOP 2>/dev/null
echo "== ledger tail:"; tail -4 "$S/.watch-cycle-exits.log" 2>/dev/null | cut -c1-200 | sed 's/^/   /'
sleep 1; rm -rf "$LAB"; echo "== lab removed: $( [ -e "$LAB" ] && echo no || echo yes)"
