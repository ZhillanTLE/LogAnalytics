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

AWK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/awk"

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


# place that knows about compression: - means stdin
# *.gz get decompressed, everything else is just read
# cat -- "$f" survives a file named -dashfile.log
emit_lines() {
	local src="$1"
	if [[ "$src" == "-" ]]; then cat
	elif [[ "$src" == *.gz ]]; then gzip -cd -- "$src"
	else	cat -- "$src"
	fi
}

# strips NUL bytes so awk doesnt misbehave on binary junk
sanitize() { LC_ALL=C tr -d '\000'; }

analyze_one() {
	local src="$1" facts="$2"
	emit_lines "$src" | sanitize \
		| awk -f "$AWK_DIR/common.awk" -f "$AWK_DIR/analyze.awk" > "$facts"
}

# how bash will read the facts file back
fact() {
	local facts="$1" type="$2"
	awk -F'\t' -v t="$type" '$1 == t { sub(/^[^\t]*\t/, ""); print }' "$facts"
}

meta() {
    local facts="$1" key="$2"
    awk -F'\t' -v k="$key" '$1 == "META" && $2 == k { print $3; exit }' "$facts"
}


# since bash only have integers, percentage in render_header is computed by a one shot awk BEGIN block
render_header() {
    local label="$1" facts="$2" total parsed unparsed pct
    total="$(meta "$facts" total)"; parsed="$(meta "$facts" parsed)"
    unparsed="$(meta "$facts" unparsed)"
    pct="$(awk -v p="$parsed" -v t="$total" 'BEGIN { printf "%.1f", (t > 0) ? 100 * p / t : 0 }')"
    printf '\n=== Log Analysis: %s  (%s lines, %s) ===\n' "$label" "$total" "$(date -Is)"
    printf '\nParsed %s lines (%s%%)   Unparsed %s   Span: %s -> %s\n' \
        "$parsed" "$pct" "$unparsed" "$(meta "$facts" first)" "$(meta "$facts" last)"
}


render_severity() {
    local facts="$1" total
    total="$(meta "$facts" parsed)"
    printf '\n%-10s %8s %7s  %s\n' "SEVERITY" "COUNT" "SHARE" "BAR"
    fact "$facts" SEV | awk -F'\t' -v total="${total:-0}" \
        -f "$AWK_DIR/common.awk" -f "$AWK_DIR/severity.awk"
}

render_top_programs() {
    local facts="$1" top="$2"
    printf '\n=== Top %s programs by error count ===\n' "$top"
    printf '%-16s %8s %8s %11s\n' "PROGRAM" "ERRORS" "TOTAL" "ERROR RATE"
    fact "$facts" PROG | sort -t"$(printf '\t')" -k3,3nr \
      | awk -F'\t' -v n="$top" 'NR <= n {
            rate = ($2 > 0) ? 100 * $3 / $2 : 0
            printf "%-16s %8d %8d %10.1f%%\n", $1, $3, $2, rate
        }'
}

render_histogram() {
    local facts="$1"
    printf '\n=== Hourly distribution (errors) ===\n'
    fact "$facts" HOUR \
        | awk -F'\t' -f "$AWK_DIR/common.awk" -f "$AWK_DIR/histogram.awk"
}

detect_burst() {
    local facts="$1"
    fact "$facts" HOUR | awk -F'\t' '
        { e[$1] = $2; if ($3 > 0) { active++; sum += $2 } }
        END {
            if (active == 0) exit
            avg = sum / active
            for (h in e) if (e[h] > peak) { peak = e[h]; ph = h }
            if (avg > 0 && peak > 10 && peak / avg >= 3)
                printf "\nBURST DETECTED  %s:00-%02d:00, %d errors, %.0fx average.\n", ph, (ph + 1) % 24, peak, peak / avg
        }'
}

write_csv() {
    local facts="$1" out="$2"
    awk -F'\t' 'BEGIN { print "metric,key,subkey,value" }
        function q(s) { if (s ~ /[",]/) { gsub(/"/, "\"\"", s); return "\"" s "\"" } return s }
        $1 == "SEV"  { print "severity," q($2) ",," $3 }
        $1 == "PROG" { print "program,"  q($2) ",total," $3; print "program," q($2) ",errors," $4 }
        $1 == "HOUR" { print "hour,"     q($2) ",errors," $3; print "hour," q($2) ",lines," $4 }
        $1 == "AUTH" { print "auth_ip,"  q($2) ",attempts," $3; print "auth_ip," q($2) ",distinct_users," $4 }
        $1 == "OOM"  { print "oom,"      q($2) ",," $3 }
        $1 == "SVC"  { print "service,"  q($3) "," q($2) "," $4 }
    ' "$facts" > "$out"
    printf '\nCSV written to %s\n' "$out"
}

render_report() {
    local label="$1" facts="$2" top="$3"
    render_header       "$label" "$facts"
    render_severity     "$facts"
    render_top_programs "$facts" "$top"
#    render_auth         "$facts" "$top"
    render_histogram    "$facts"
    detect_burst        "$facts"
}


# Pattern extraction additions
render_auth() {
	local facts="$1" top="$2"
	if [[ ! -s "$facts" ]] || ! fact "$facts" AUTH | grep -q . ; then return 0; fi
    	printf '\n=== Failed authentication by source IP ===\n'
    	printf '%-18s %9s %12s %12s %11s\n' "IP" "ATTEMPTS" "USERS TRIED" "FIRST SEEN" "LAST SEEN"
    	fact "$facts" AUTH | sort -t"$(printf '\t')" -k2,2nr \
      	| awk -F'\t' -v n="$top" 'NR <= n { printf "%-18s %9d %12d %12s %11s\n", $1, $2, $3, $4, $5 }'
}

# Log discovery additions
discover_logs() {
	local dir="$1"
	find "$dir" -type f \( -name '*.log' -o -name '*.log.[0-9]*' \
         -o -name 'syslog*' -o -name '*.gz' \) -print0 | sort -z
}
 #analyze targets updated
analyze_targets() {
    local top="$1" csv="$2"; shift 2
    local -a sources=()
    local t f i=0

    for t in "$@"; do
        if   [[ "$t" == "-" ]]; then sources+=("-")
        elif [[ -d "$t"     ]]; then
            while IFS= read -r -d '' f; do sources+=("$f"); done < <(discover_logs "$t")
        elif [[ -f "$t"     ]]; then sources+=("$t")
        else warn "skipping unreadable target: $t"
        fi
    done
    (( ${#sources[@]} > 0 )) || die "no readable logs found"

    for f in "${sources[@]}"; do
        i=$(( i + 1 ))
        analyze_one "$f" "$TMP_DIR/facts.$i"
        render_report "$f" "$TMP_DIR/facts.$i" "$top"
    done

    if (( ${#sources[@]} > 1 )); then
        for f in "${sources[@]}"; do emit_lines "$f"; done | sanitize \
            | awk -f "$AWK_DIR/common.awk" -f "$AWK_DIR/analyze.awk" > "$TMP_DIR/facts.all"
        render_report "ALL FILES (${#sources[@]})" "$TMP_DIR/facts.all" "$top"
        write_csv "$TMP_DIR/facts.all" "$csv"
    else
        write_csv "$TMP_DIR/facts.1" "$csv"
    fi
}


# Rotation additions

assert_inside() {
    local root="$1" path="$2" rroot rpath
    rroot="$(realpath -- "$root")"  || die "cannot resolve $root"
    rpath="$(realpath -m -- "$path")" || die "cannot resolve $path"
    [[ "$rpath" == "$rroot" || "$rpath" == "$rroot"/* ]] \
        || die "refusing to touch '$path': outside '$root'"
}

gzip_to() { gzip -c -- "$1" > "$2" && rm -f -- "$1"; }

act() {
    local desc="$1"; shift
    [[ "${1:-}" == "--" ]] && shift
    if (( APPLY )); then
        printf '  %s\n' "$desc"
        "$@"
    else
        printf '  would %s\n' "$desc"
    fi
}

rotate_one() {
    local log="$1" keep="$2" compress="$3" copytrunc="$4" max_size="$5"
    local dir base mode owner size i src dst

    dir="${log%/*}"; base="${log##*/}"
    [[ -f "$log" ]] || { warn "not a regular file: $log"; return 0; }

    size="$(stat -c '%s' -- "$log")"
    if (( max_size > 0 && size < max_size )); then
        printf '  skip %s (%s bytes, below --max-size %s)\n' "$base" "$size" "$max_size"
        return 0
    fi

    mode="$(stat -c '%a'    -- "$log")"
    owner="$(stat -c '%U:%G' -- "$log")"
    warn_if_open "$log"

    for i in $(seq "$(( keep + 3 ))" -1 "$keep"); do
        for dst in "$dir/$base.$i" "$dir/$base.$i.gz"; do
            [[ -e "$dst" ]] || continue
            assert_inside "$dir" "$dst"
            act "rm      ${dst##*/}  (beyond --keep $keep)" -- rm -f -- "$dst"
        done
    done

    for (( i = keep - 1; i >= 2; i-- )); do
        for src in "$dir/$base.$i" "$dir/$base.$i.gz"; do
            [[ -e "$src" ]] || continue
            dst="${src%.gz}"; dst="${dst%."$i"}.$(( i + 1 ))"
            [[ "$src" == *.gz ]] && dst="$dst.gz"
            assert_inside "$dir" "$dst"
            act "mv      ${src##*/}  ->  ${dst##*/}" -- mv -- "$src" "$dst"
        done
    done

    if [[ -e "$dir/$base.1" ]]; then
        if (( compress )); then
            assert_inside "$dir" "$dir/$base.2.gz"
            act "gzip    $base.1  ->  $base.2.gz" -- gzip_to "$dir/$base.1" "$dir/$base.2.gz"
        else
            assert_inside "$dir" "$dir/$base.2"
            act "mv      $base.1  ->  $base.2" -- mv -- "$dir/$base.1" "$dir/$base.2"
        fi
    fi

    assert_inside "$dir" "$dir/$base.1"
    if (( copytrunc )); then
        act "cp      $base  ->  $base.1 (inode preserved)" -- cp -p -- "$log" "$dir/$base.1"
        act "trunc   $base (in place, same inode)"         -- truncate -s 0 -- "$log"
    else
        act "mv      $base  ->  $base.1"                   -- mv -- "$log" "$dir/$base.1"
        act "create  $base (mode $mode, owner $owner)"     -- install -m "$mode" /dev/null "$log"
    fi
}

rotate_target() {
    local target="$1" keep="$2" compress="$3" copytrunc="$4" max_size="$5"
    local f
    if (( APPLY )); then
        printf '\n=== Rotation for %s (APPLYING) ===\n' "$target"
    else
        printf '\n=== Rotation plan for %s (DRY RUN) ===\n' "$target"
    fi
    if [[ -d "$target" ]]; then
        while IFS= read -r -d '' f; do
            rotate_one "$f" "$keep" "$compress" "$copytrunc" "$max_size"
        done < <(find "$target" -maxdepth 1 -type f -name '*.log' -print0 | sort -z)
    elif [[ -f "$target" ]]; then
        rotate_one "$target" "$keep" "$compress" "$copytrunc" "$max_size"
    else
        die "no such file or directory: $target"
    fi
    (( APPLY )) || printf '  (nothing was changed. re-run with --apply to act)\n'
}

# Rotations 1.1 additions
holders_of() {
    local target fd link pid
    target="$(realpath -- "$1")" || return 0
    shopt -s nullglob
    for fd in /proc/[0-9]*/fd/*; do
        link="$(readlink -- "$fd" 2>/dev/null)" || continue
        [[ "$link" == "$target" ]] || continue
        pid="${fd#/proc/}"; pid="${pid%%/fd/*}"
        printf '%s %s\n' "$pid" "$(cat "/proc/$pid/comm" 2>/dev/null || printf '?')"
    done | sort -u
    shopt -u nullglob
}

warn_if_open() {
    local log="$1" pid name base="${1##*/}"
    while read -r pid name; do
        [[ -n "$pid" ]] || continue
        printf '  WARNING: %s is held open by pid %s (%s).\n' "$base" "$pid" "$name"
        printf '           After rotation it will keep writing to the RENAMED file, and the\n'
        printf '           new %s will stay empty until the process reopens it.\n' "$base"
        printf '           Send SIGHUP after rotating, or use --copytruncate.\n'
    done < <(holders_of "$log")
}


main "$@"
