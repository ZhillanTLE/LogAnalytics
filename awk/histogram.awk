# awk/histogram.awk - renders the hourly bar chart. Needs common.awk.
{ e[$1] = $2; if ($2 > max) max = $2; if ($3 > 0) { active++; sum += $2 } }
END {
    avg = (active > 0) ? sum / active : 0
    for (h = 0; h < 24; h++) {
        hh = sprintf("%02d", h)
        if (!(hh in e)) continue
        bars = (max > 0) ? int(e[hh] * 24 / max) : 0
        if (e[hh] > 0 && bars < 1) bars = 1
        note = ""
        if (avg > 0 && e[hh] > 10 && e[hh] / avg >= 3)
            note = sprintf("   <-- BURST: %.0fx the hourly average of %.1f", e[hh] / avg, avg)
        printf "%s |%-24s %s%s\n", hh, rep("#", bars), commify(e[hh]), note
    }
}
