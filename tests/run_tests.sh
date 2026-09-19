#!/usr/bin/env bash
# tests/run_tests.sh - every check the brief asks for, in one command.
set -uo pipefail

LOGS="${1:-/tmp/logs}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0

check() {                       # check "name" command...
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '  PASS  %s\n' "$name"; pass=$(( pass + 1 ))
    else
        printf '  FAIL  %s (exit %s)\n' "$name" "$?"; fail=$(( fail + 1 ))
    fi
}

cd "$HERE"
./mklogs.sh "$LOGS" >/dev/null 2>&1

check "syntax"            bash -n loganalyze.sh
check "help"              ./loganalyze.sh --help
check "single file"       ./loganalyze.sh "$LOGS/auth.log" --top 5
check "directory"         ./loganalyze.sh "$LOGS" --top 5
check "gzip"              ./loganalyze.sh "$LOGS/syslog.gz"
check "empty file"        ./loganalyze.sh "$LOGS/empty.log"
check "binary junk"       ./loganalyze.sh "$LOGS/bad.log"
check "no trailing nl"    ./loganalyze.sh "$LOGS/nonl.log"
check "spaces in name"    ./loganalyze.sh "$LOGS/weird dir"
check "rotate dry run"    ./loganalyze.sh "$LOGS/myapp" --rotate --keep 3 --compress
check "rotate keep 1"     ./loganalyze.sh "$LOGS/myapp" --rotate --keep 1
check "max-size skip"     ./loganalyze.sh "$LOGS/myapp" --rotate --max-size 10M
command -v shellcheck >/dev/null && check "shellcheck" shellcheck loganalyze.sh mklogs.sh

if cat "$LOGS/syslog" | ./loganalyze.sh - >/dev/null 2>&1; then
    printf '  PASS  stdin\n'; pass=$(( pass + 1 ))
else
    printf '  FAIL  stdin\n'; fail=$(( fail + 1 ))
fi

before="$(ls -li "$LOGS/myapp")"
./loganalyze.sh "$LOGS/myapp" --rotate --keep 3 >/dev/null 2>&1
if [[ "$before" == "$(ls -li "$LOGS/myapp")" ]]; then
    printf '  PASS  dry run changed nothing\n'; pass=$(( pass + 1 ))
else
    printf '  FAIL  dry run CHANGED FILES\n'; fail=$(( fail + 1 ))
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
