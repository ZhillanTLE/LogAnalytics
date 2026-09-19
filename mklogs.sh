#!/usr/bin/env bash
set -euo pipefail

HOST="webserver"

stamp() { date -d "@$1" +'%b %e %H:%M:%S'; }

emit_normal() {
    local base="$1" h i t
    for h in 0 1 2 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23; do
        for i in 1 2 3 4 5 6; do
            t=$(( base + h * 3600 + i * 137 ))
            printf '%s %s CRON[%s]: pam_unix(cron:session): session opened for user root\n' \
                "$(stamp "$t")" "$HOST" "$(( 2000 + i ))"
        done
        for i in 1 2; do
            t=$(( base + h * 3600 + i * 411 ))
            printf '%s %s sshd[%s]: Accepted password for kali from 192.168.1.20 port %s ssh2\n' \
                "$(stamp "$t")" "$HOST" "$(( 3000 + i ))" "$(( 50000 + i ))"
        done
    done
}

emit_burst() {
    local base="$1" i t u
    local users=(admin root test guest oracle postgres mysql ubuntu pi \
                 user1 user2 deploy git ftp www backup nagios)
    for i in $(seq 1 341); do
        t=$(( base + 3 * 3600 + i * 4 ))
        u="${users[$(( i % 17 ))]}"
        printf '%s %s sshd[%s]: Failed password for invalid user %s from 10.0.0.5 port %s ssh2\n' \
            "$(stamp "$t")" "$HOST" "$(( 4000 + i ))" "$u" "$(( 40000 + i ))"
    done
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        t=$(( base + 22 * 3600 + i * 90 ))
        printf '%s %s sshd[%s]: Failed password for root from 192.168.1.77 port %s ssh2\n' \
            "$(stamp "$t")" "$HOST" "$(( 5000 + i ))" "$(( 30000 + i ))"
    done
}

emit_oom() {
    local base="$1"
    printf '%s %s kernel: [ 8123.44] mysqld invoked oom-killer: gfp_mask=0x100cca\n' \
        "$(stamp "$(( base + 4 * 3600 + 12 ))")" "$HOST"
    printf '%s %s kernel: [ 8123.51] Out of memory: Killed process 8123 (mysqld) total-vm:2048000kB\n' \
        "$(stamp "$(( base + 4 * 3600 + 13 ))")" "$HOST"
    printf '%s %s kernel: [ 9001.02] Out of memory: Killed process 9001 (python3) total-vm:900000kB\n' \
        "$(stamp "$(( base + 17 * 3600 + 5 ))")" "$HOST"
}

emit_services() {
    local base="$1" i
    for i in 1 2 3; do
        printf '%s %s systemd[1]: Stopping The nginx HTTP server...\n' \
            "$(stamp "$(( base + i * 5000 ))")" "$HOST"
        printf '%s %s systemd[1]: Started The nginx HTTP server.\n' \
            "$(stamp "$(( base + i * 5000 + 3 ))")" "$HOST"
    done
}

emit_garbage() {
    local i
    printf -- '--- last message repeated 3 times ---\n'
    printf '    at java.base/java.lang.Thread.run(Thread.java:829)\n'
    printf '\n'
    for i in 1 2 3; do
        printf 'not a syslog line at all %s\n' "$i"
    done
}

make_edge_cases() {
    local dir="$1"
    : > "$dir/empty.log"
    head -c 4096 /dev/urandom > "$dir/bad.log"
    printf 'Sep  5 01:02:03 h prog[1]: no newline at the end of this file' > "$dir/nonl.log"
    mkdir -p "$dir/weird dir"
    printf 'Sep  5 01:02:03 h prog[1]: hello from a filename with spaces\n' > "$dir/weird dir/my log.log"
}

make_myapp() {
    local dir="$1/myapp" i
    mkdir -p "$dir"
    printf 'Sep  5 01:00:00 h myapp[1]: application started\n' > "$dir/app.log"
    chmod 640 "$dir/app.log"
    for i in 1 2 3 4 5; do
        printf 'old generation %s\n' "$i" > "$dir/app.log.$i"
    done
    gzip -f "$dir/app.log.3" "$dir/app.log.4" "$dir/app.log.5"
}

main() {
    local dir="${1:-/tmp/logs}" base
    mkdir -p "$dir"
    base="$(date -d 'today 00:00' +%s)"

    { emit_normal "$base"; emit_burst "$base"; emit_garbage; } | sort -k1,2 > "$dir/auth.log"
    { emit_normal "$base"; emit_oom "$base"; emit_services "$base"; } > "$dir/syslog"
    gzip -kf "$dir/syslog" 2>/dev/null || { gzip -c "$dir/syslog" > "$dir/syslog.gz"; }

    make_edge_cases "$dir"
    make_myapp "$dir"

    printf 'generated in %s\n' "$dir" >&2
    wc -l "$dir/auth.log" "$dir/syslog" >&2
}

main "$@"
