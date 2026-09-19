# awk/analyze.awk -> one pass over log lines; emits tab-separated facts.

BEGIN { OFS = "\t" }

{ total++ }

# Anything that is not "Mon [D]D HH:MM:SS " is not a syslog record.
!/^[A-Z][a-z][a-z] +[0-9][0-9]? [0-9][0-9]:[0-9][0-9]:[0-9][0-9] / {
    unparsed++
    next
}

{
	parsed++
	hour = substr($3, 1, 2)
	ts = $1 " " $2 " " substr($3, 1, 5)
	if (first == "") first = ts
	last = ts
	tag = $5
	sub(/:$/, "", tag)
   	 if (match(tag, /\[[0-9]+\]$/)) {
		 pid  = substr(tag, RSTART + 1, RLENGTH - 2)
		 prog = substr(tag, 1, RSTART - 1)
    	 } else {
       	 pid  = "-"
       	 prog = tag
	 }

	msg = ""
	for (i =6; i <= NF; i++) msg = msg (i>6? " " : "") $i

	sev = severity(msg)
	sev_count[sev]++
	prog_total[prog]++
	hour_all[hour]++
	if (sev == "ERROR" || sev == "CRITICAL") {
		prog_err[prog]++
		hour_err[hour]++
	}
}

END {
    print "META", "total",    total + 0
    print "META", "parsed",   parsed + 0
    print "META", "unparsed", unparsed + 0
    print "META", "first",    (first == "" ? "-" : first)
    print "META", "last",     (last  == "" ? "-" : last)

    for (s in sev_count)  print "SEV",  s, sev_count[s]
    for (p in prog_total) print "PROG", p, prog_total[p], prog_err[p] + 0
    for (h in hour_all)   print "HOUR", h, hour_err[h] + 0, hour_all[h]
}
