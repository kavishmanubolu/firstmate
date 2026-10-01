#!/usr/bin/env bash
# Live driver: real fm-spawn.sh / fm-teardown.sh against a guarded fm-lab-*
# Herdr session (all herdr calls routed through bin/fm-herdr-lab.sh run).
set -u
ROOT=${ROOT:?}
HELPER="$ROOT/bin/fm-herdr-lab.sh"
REAL_HERDR=$(command -v herdr)
ORIG_PATH=$PATH
TMP=$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd -P)/fm-dn-live.XXXXXX")
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
export REAL_HERDR ORIG_PATH HELPER

cat > "$FAKEBIN/herdr" <<'SH'
#!/usr/bin/env bash
set -u
args=("$@"); n=${#args[@]}
if [ "$n" -ge 2 ] && [ "${args[$((n-2))]}" = --session ] && [ "${args[$((n-1))]}" = "$HERDR_LAB_SESSION" ]; then
  unset "args[$((n-1))]" "args[$((n-2))]"
fi
set -- "${args[@]}"
if [ "${1:-}" = --version ]; then
  exec env PATH="$ORIG_PATH" "$REAL_HERDR" "$@" --session "$HERDR_LAB_SESSION"
fi
exec env PATH="$ORIG_PATH" "$HELPER" run "$HERDR_LAB_SESSION" "$@"
SH
chmod +x "$FAKEBIN/herdr"

unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION
export FM_GATE_REFUSE_BYPASS=1
SESSION=$(PATH="$ORIG_PATH" "$HELPER" name fm-dn-live)
export HERDR_SESSION=$SESSION HERDR_LAB_SESSION=$SESSION
echo "lab session: $SESSION"
WTS=""
cleanup() {
  local wt
  for wt in $WTS; do [ -d "$wt" ] && treehouse return --force "$wt" >/dev/null 2>&1; done
  PATH="$ORIG_PATH" "$HELPER" teardown "$SESSION" >/dev/null 2>&1 && echo "lab teardown: ok"
  rm -rf "$TMP"
}
trap cleanup EXIT
PATH="$ORIG_PATH" "$HELPER" provision "$SESSION" >/dev/null || { echo "provision failed"; exit 1; }
export PATH="$FAKEBIN:$PATH"
lab() { PATH="$ORIG_PATH" "$HELPER" run "$SESSION" "$@"; }

FAILS=0
ok() { echo "PASS - $*"; }
bad() { echo "FAIL - $*"; FAILS=$((FAILS+1)); }

HOME_DIR="$TMP/home"
PROJ="$TMP/wheelhouse"
mkdir -p "$HOME_DIR/state" "$HOME_DIR/config"
touch "$HOME_DIR/state/.last-watcher-beat"
mkdir -p "$PROJ"; git -C "$PROJ" init -q; echo x > "$PROJ/README.md"
git -C "$PROJ" add README.md; git -C "$PROJ" -c user.name=t -c user.email=t@e.invalid commit -qm init
git clone --quiet --bare "$PROJ" "$PROJ.origin.git"; git -C "$PROJ" remote add origin "file://$PROJ.origin.git"

brief() { mkdir -p "$HOME_DIR/data/$1"; printf '# Task\n## Captain'"'"'s intent\nfixture %s\n\n## Firstmate spec\nlive display-name check\n' "$1" > "$HOME_DIR/data/$1/brief.md"; }
spawn() { local id=$1; shift
  FM_SPAWN_NO_GUARD=1 FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$ROOT" \
    "$ROOT/bin/fm-spawn.sh" "$id" "$PROJ" "sh -c 'while :; do sleep 60; done'" --mode no-mistakes --yolo off --backend herdr "$@"
}
teardown() { FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$HOME_DIR/state" \
  FM_DATA_OVERRIDE="$HOME_DIR/data" FM_CONFIG_OVERRIDE="$HOME_DIR/config" "$ROOT/bin/fm-teardown.sh" "$1" --force; }
remember() { WTS="$WTS $(grep '^worktree=' "$HOME_DIR/state/$1.meta" | cut -d= -f2-)"; }
label_of() { local ws; ws=$(grep '^herdr_workspace_id=' "$HOME_DIR/state/$1.meta" | cut -d= -f2-)
  lab workspace get "$ws" | jq -r '.result.workspace.label'; }
token_of() { grep '^projection_id=' "$HOME_DIR/state/$1.herdr-presentation" | cut -d= -f2-; }
tablabel_of() { local ws; ws=$(grep '^herdr_workspace_id=' "$HOME_DIR/state/$1.meta" | cut -d= -f2-)
  lab tab list --workspace "$ws" | jq -r '.result.tabs[0].label'; }

# Anchor (flat, opted out) establishes the firstmate parent workspace.
printf 'off\n' > "$HOME_DIR/config/herdr-presentation-spaces"
brief anchor
spawn anchor > "$TMP/anchor.out" 2> "$TMP/anchor.err" || { echo "anchor spawn failed: $(cat "$TMP/anchor.err")"; exit 1; }
remember anchor
printf 'on\n' > "$HOME_DIR/config/herdr-presentation-spaces"

echo "== S1 derived name drops repeated project prefix, title-cases words =="
brief wheelhouse-sidebar-names
spawn wheelhouse-sidebar-names > "$TMP/s1.out" 2> "$TMP/s1.err" || bad "S1 spawn failed: $(cat "$TMP/s1.err")"
remember wheelhouse-sidebar-names
L=$(label_of wheelhouse-sidebar-names); T=$(token_of wheelhouse-sidebar-names)
echo "workspace label: $L"; echo "task tab label:  $(tablabel_of wheelhouse-sidebar-names)"
echo "record: $(cat "$HOME_DIR/state/wheelhouse-sidebar-names.herdr-display-name")"
[ "$L" = "└ Sidebar Names · p:$T" ] && ok "S1 derived label is '└ Sidebar Names · p:<token>'" || bad "S1 label $L"
[ "$(tablabel_of wheelhouse-sidebar-names)" = fm-wheelhouse-sidebar-names ] && ok "S1 task tab keeps exact fm-<id>" || bad "S1 tab label"

echo "== S2 explicit --display-name wins over derived =="
brief wheelhouse-merge-conductor
spawn wheelhouse-merge-conductor --display-name "Merge Boss" > "$TMP/s2.out" 2> "$TMP/s2.err" || bad "S2 spawn failed: $(cat "$TMP/s2.err")"
remember wheelhouse-merge-conductor
L=$(label_of wheelhouse-merge-conductor); T=$(token_of wheelhouse-merge-conductor)
echo "workspace label: $L"
[ "$L" = "└ Merge Boss · p:$T" ] && ok "S2 explicit display name wins" || bad "S2 label $L"

echo "== S3 adversarial: name forging ' · p:' separator and overlong text is sanitized =="
brief forge-attempt
spawn forge-attempt "--display-name=Evil · p:AAAAAAAAAAAAAAAAAAAAAA and a very long tail of words" > "$TMP/s3.out" 2> "$TMP/s3.err" || bad "S3 spawn failed: $(cat "$TMP/s3.err")"
remember forge-attempt
L=$(label_of forge-attempt); T=$(token_of forge-attempt)
echo "workspace label: $L"
PARSED=$(bash -c '. "$1/bin/backends/herdr.sh"; fm_backend_herdr_projection_workspace_label_token "$2"' _ "$ROOT" "$L")
echo "token parsed back from live title: $PARSED (journal token $T)"
NAME=${L#└ }; NAME=${NAME% · p:*}
case "$L" in *AAAAAAAAAAAAAAAAAAAAAA*·*) bad "S3 forged token survived";; esac
[ "$PARSED" = "$T" ] && [ "${#NAME}" -le 28 ] && ok "S3 title parses to the real token only; name '${NAME}' (${#NAME} chars <= 28)" || bad "S3 parse=$PARSED name=$NAME"

echo "== S4 adversarial: --display-name with nothing label-safe refuses before any state =="
brief refused-name
if spawn refused-name --display-name '::: ··· ' > "$TMP/s4.out" 2> "$TMP/s4.err"; then bad "S4 spawn unexpectedly succeeded"; remember refused-name
else
  echo "stderr: $(cat "$TMP/s4.err")"
  ls "$HOME_DIR/state" | grep -q '^refused-name\.' && bad "S4 left state: $(ls "$HOME_DIR/state" | grep refused-name)" || ok "S4 refused with no task state created"
fi
if spawn refused-name2 --display-name= > "$TMP/s4b.out" 2> "$TMP/s4b.err"; then bad "S4b empty accepted"; else echo "stderr: $(cat "$TMP/s4b.err")"; ok "S4b empty --display-name= refused"; fi

echo "== S5 teardown retires the display-name record with its journal and workspace =="
for id in wheelhouse-sidebar-names wheelhouse-merge-conductor forge-attempt; do
  ws=$(grep '^herdr_workspace_id=' "$HOME_DIR/state/$id.meta" | cut -d= -f2-)
  teardown "$id" > "$TMP/td-$id.out" 2> "$TMP/td-$id.err" || bad "S5 teardown $id failed: $(cat "$TMP/td-$id.err")"
  if [ ! -e "$HOME_DIR/state/$id.herdr-display-name" ] && [ ! -e "$HOME_DIR/state/$id.herdr-presentation" ] && ! lab workspace get "$ws" >/dev/null 2>&1; then
    ok "S5 $id: record, journal, and workspace gone"
  else bad "S5 $id leftovers: $(ls "$HOME_DIR/state" | grep "^$id\." | tr '\n' ' ')"; fi
done

echo "== S6 existing workspace is never renamed: a pre-existing legacy-labeled workspace survives a new spawn =="
LEG=$(lab workspace create --cwd "$PROJ" --label "└ legacy-task · p:BBBBBBBBBBBBBBBBBBBBBB" --no-focus | jq -r '.result.workspace.workspace_id')
brief wheelhouse-after-legacy
spawn wheelhouse-after-legacy > "$TMP/s6.out" 2> "$TMP/s6.err" || bad "S6 spawn failed: $(cat "$TMP/s6.err")"
remember wheelhouse-after-legacy
echo "new worker label: $(label_of wheelhouse-after-legacy)"
LL=$(lab workspace get "$LEG" | jq -r '.result.workspace.label')
echo "legacy workspace label after spawn: $LL"
[ "$LL" = "└ legacy-task · p:BBBBBBBBBBBBBBBBBBBBBB" ] && ok "S6 legacy label untouched" || bad "S6 legacy renamed: $LL"
P=$(bash -c '. "$1/bin/backends/herdr.sh"; fm_backend_herdr_projection_workspace_label_token "$2"' _ "$ROOT" "$LL")
[ "$P" = BBBBBBBBBBBBBBBBBBBBBB ] && ok "S6 legacy label still parses to its token" || bad "S6 legacy parse '$P'"
echo "-- full sidebar listing --"
lab workspace list | jq -r '.result.workspaces[].label'
teardown wheelhouse-after-legacy > /dev/null 2>&1 || true
teardown anchor > /dev/null 2>&1 || true
echo "FAILS=$FAILS"
exit "$FAILS"
