# awk/severity.awk - renders the severity table. Needs common.awk and -v total=N
{ c[$1] = $2 }
END {
    n = split("CRITICAL ERROR WARNING INFO", order, " ")
    for (i = 1; i <= n; i++) {
        s = order[i]; v = c[s] + 0
        share = (total > 0) ? 100 * v / total : 0
        printf "%-10s %8s %6.1f%%  %s\n", s, commify(v), share, rep("#", int(share / 2))
    }
}
