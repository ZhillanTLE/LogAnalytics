# Log Analytics & Rotation Engine

Log analysis and rotation engine in Bash + awk. OS assignment, Programming 1 (Type 4).

## What it does

**Analysis** parses syslog-format logs, classifies severity, aggregates by
program/severity/hour, extracts failed-auth attempts by source IP, OOM kills and
service events, and flags bursts and statistical anomalies. Outputs an aligned
report, an ASCII histogram, and `log_report.csv`.

**Rotation** rotates logs the way logrotate does (rename, compress, keep N,
delete the rest). Defaults to a dry run, warns when a rotation target is still
held open by a running process, and preserves permissions.

## Requirements

Bash 4+, awk (mawk or gawk), coreutils, gzip. Tested on Kali (Debian), targeted
at Ubuntu Server 24.04.

How to run
```
git clone git@github.com:ZhillanTLE/loganalyze.git
cd loganalyze
chmod +x loganalyze.sh mklogs.sh tests/run_tests.sh
```
Generate test data with known answers, then analyse it:
```
./mklogs.sh /tmp/logs                     # plants 341 failed logins from 10.0.0.5, 17 users, hour 03
./loganalyze.sh /tmp/logs/auth.log --top 5
./loganalyze.sh /tmp/logs --top 5         # a directory, plain and .gz together
cat /tmp/logs/syslog | ./loganalyze.sh -  # stdin, so it composes in a pipeline
```
Rotation is a dry run by default as it prints the exact sequence of renames,
compressions and deletions, and changes nothing. Add `--apply` to act:
```
./loganalyze.sh /tmp/logs/myapp --rotate --keep 3 --compress
./loganalyze.sh /tmp/logs/myapp --rotate --keep 3 --compress --apply
./loganalyze.sh /tmp/logs/myapp --rotate --keep 3 --copytruncate --apply
```
To see the open-descriptor warning, hold the log open first:
```
tail -f /tmp/logs/myapp/app.log >/dev/null &
./loganalyze.sh /tmp/logs/myapp --rotate --keep 3
kill %1
```
Verify everything:
```
./tests/run_tests.sh
bash -n loganalyze.sh && shellcheck loganalyze.sh
```
