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
	if (msg ~ /Failed password|Invalid user|authentication failure|Failed publickey/){
		ip = auth_ip(msg)
		if (ip != ""){
			user = auth_user(msg)
			auth_attempts[ip]++
			if (auth_seen[ip, user]++ == 0) auth_users[ip]++
			if (!(ip in auth_first)) auth_first[ip] = $3
			auth_last[ip] = $3
		}
	}
	
	if (msg ~ /[Oo]ut of memory|oom-kill|invoked oom-killer|Killed process/) {
      		victim = "unknown"
        	if (match(msg, /\([^)]+\)/)) victim = substr(msg, RSTART + 1, RLENGTH - 2)
        	oom[victim]++
    	}

	if (msg ~ /^(Started|Starting|Stopped|Stopping|Reloading|Restarting) /) {
        	split(msg, sw, " ")
        	unit = msg
        	sub(/^[A-Za-z]+ +/, "", unit)
        	sub(/[.]+$/, "", unit)
        	svc[sw[1], unit]++
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
    for (a in auth_attempts)
	print "AUTH", a, auth_attempts[a], auth_users[a], auth_first[a], auth_last[a]
    for (v in oom) print "OOM", v, oom[v]
    for (k in svc) { split(k, parts, SUBSEP); print "SVC", parts[1], parts[2], svc[k] }
}
