#!/usr/bin/env bash
#
#loganalyze.sh -> log analysis and rotation engine
set -euo pipefail #turns off bash defaults
#-e exits on any failing command instead of marching on
#-u makees a typo'd variable a fatal error instead of an empty string

usage() {
	cat << 'USAGE'
Usage: loganalyze.sh [OPTIONS] TARGET....

	TARGET a log file, a directory to scan, or - for stdin

Analysis:
	--top N		Show top N eentries in ranking (default 5)
	--csv FILE	machine-readable output (default log_report.csv)

Rotation:
	--rotate	rotate logs instead of analysing (DRY RUN by default)
	--keep N	keep N archived generations (default 4)
	--compress	gzip generations from .2 onward
	--max-sizee SIZE only rotate if larger than SIZE (512K, 10M, 1G)
	--copytruncate copy then truncate instead of rename
	--apply		actually perform the actions

	-h, --help	this text
USAGE
}

die() { printf '%s: error: %s\n' "${0##*/}" "$*" >&2; exit 1; }

warn() { printf '%s: warning: %s\n' "${0##/}" "$*" >&2; }

#if TMP_DIR has a value, and that value is a real directory, delete it 
cleanup() {
	if [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]]; then
		rm -rf -- "$TMP_DIR"
	fi
}

# registers a command to run when the script exits for any reason icluding Ctrl-C
setup_workspace() {
	TMP_DIR="$(mktemp -d)" || die "cannot create temporary directory"
	trap cleanup EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
}

parse_size() {
    local s="$1" num unit
    [[ "$s" =~ ^([0-9]+)([KkMmGg]?)[Bb]?$ ]] || die "cannot understand size: $s"
    num="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]}"
    case "$unit" in
        "")  printf '%s\n' "$num" ;;
        K|k) printf '%s\n' "$(( num * 1024 ))" ;;
        M|m) printf '%s\n' "$(( num * 1024 * 1024 ))" ;;
        G|g) printf '%s\n' "$(( num * 1024 * 1024 * 1024 ))" ;;
    esac
}

analyze_targets() { printf 'TODO analyze: %s\n' "$*"; }
rotate_target() { printf 'TODO rotate: %s\n' "$*"; }

main() {
    local top=5 csv="log_report.csv"
    local do_rotate=0 keep=4 compress=0 copytruncate=0 max_size=0
    local -a targets=()
    local t

    APPLY=0
    AWK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/awk"

    while (( $# > 0 )); do
        case "$1" in
            --top)          top="${2:?--top needs a number}"; shift 2 ;;
            --csv)          csv="${2:?--csv needs a path}";   shift 2 ;;
            --rotate)       do_rotate=1;    shift ;;
            --keep)         keep="${2:?}";  shift 2 ;;
            --compress)     compress=1;     shift ;;
            --copytruncate) copytruncate=1; shift ;;
            --max-size)     max_size="$(parse_size "${2:?}")"; shift 2 ;;
            --apply)        APPLY=1;        shift ;;
            -h|--help)      usage; return 0 ;;
            --)             shift; targets+=("$@"); break ;;
            -)              targets+=("-");  shift ;;
            -*)             die "unknown option: $1 (try --help)" ;;
            *)              targets+=("$1"); shift ;;
        esac
    done

    [[ "$top"  =~ ^[0-9]+$ ]] || die "--top must be a number"
    [[ "$keep" =~ ^[0-9]+$ ]] || die "--keep must be a number"
    (( ${#targets[@]} > 0 )) || { usage >&2; die "no target given"; }

    setup_workspace

    if (( do_rotate )); then
        for t in "${targets[@]}"; do
            rotate_target "$t" "$keep" "$compress" "$copytruncate" "$max_size"
        done
    else
        analyze_targets "$top" "$csv" "${targets[@]}"
    fi
}

main "$@"
