# awk/common.awk -> helpers shared by every awk stage

function commify(n, s, r){
	s = sprintf("%d", n); r = ""
	while (length(s) > 3) {
		r = "," substr(s, length(s) - 2) r
		s = substr(s, 1, length(s) - 3)
	}
	return s r
}

function rep(c, n, s) {
	s = ""
	while (n-- > 0) s = s c
	return s
}

function severity(m , l) {
	l = tolower(m)
	 if (l ~ /panic|fatal|emerg|segfault|oom-kill|out of memory/) return "CRITICAL"
   	 if (l ~ /error|failed|failure|denied|refused|cannot|unable|timed out|timeout/) return "ERROR"
   	 if (l ~ /warn|deprecat|retry|unreachable|invalid/) return "WARNING"
   	 return "INFO"
}


