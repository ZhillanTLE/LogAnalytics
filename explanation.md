# explanation.md — loganalyze.sh

Programming 1 (Type 4): Log Analytics & Rotation Engine
Class KKI · Group of 2

| Name | NPM |
|---|---|
| Zhillan Baniaksa | 2506637174 |
| Maglio Razzy Effendy | 2506553616 |

## Who wrote what

**Zhillan** built the core pipeline: project skeleton and option parsing,
`mklogs.sh` (the log generator with the planted 341-attempt burst), the
syslog parser (`awk/analyze.awk`, `awk/common.awk`), severity classification,
program/severity/hour aggregation, failed-auth/OOM/service-event extraction,
burst detection, the discovery + `.gz` + stdin support, the full rotation
engine (dry run, `--apply`, `assert_inside` containment, `--copytruncate`,
the `/proc/*/fd` open-descriptor scan and warning), and the self-designed
**anomaly scoring** feature (`detect_anomalies`).

**Razzy** wrote the second self-designed feature, **disk-space projection**
(`project_disk_growth`), and this file.

## How to run

```bash
chmod +x loganalyze.sh mklogs.sh tests/run_tests.sh

# generate test data with known answers (341 failed logins from 10.0.0.5, hour 03)
./mklogs.sh /tmp/logs

# analyse
./loganalyze.sh /tmp/logs/auth.log --top 5     # single file
./loganalyze.sh /tmp/logs --top 5              # a directory, plain + .gz together
cat /tmp/logs/syslog | ./loganalyze.sh -       # stdin, so it composes in a pipeline

# rotate — dry run by default, nothing is touched until --apply
./loganalyze.sh /tmp/logs/myapp --rotate --keep 3 --compress
./loganalyze.sh /tmp/logs/myapp --rotate --keep 3 --compress --apply
./loganalyze.sh /tmp/logs/myapp --rotate --keep 3 --copytruncate --apply

# to see the open-descriptor warning
tail -f /tmp/logs/myapp/app.log >/dev/null &
./loganalyze.sh /tmp/logs/myapp --rotate --keep 3
kill %1

# verify everything
./tests/run_tests.sh
bash -n loganalyze.sh && shellcheck loganalyze.sh
```

Flags: `--top N`, `--csv FILE`, `--rotate`, `--keep N`, `--compress`,
`--max-size SIZE` (e.g. `512K`, `10M`, `1G`), `--copytruncate`, `--apply`,
`--anomaly-k N` (default 2), `-h/--help`.

## What it does, and why

### Parsing and severity

Only lines matching the syslog record shape (`Mon D HH:MM:SS host tag: msg`)
are parsed; everything else is counted as `unparsed` rather than silently
dropped, and both counts are printed in the header — a parser that quietly
discards a chunk of the file looks correct while hiding real data loss.

Severity is assigned by keyword, checked in this order so that a message
matching more than one category still lands on the most serious one:
`CRITICAL` (panic/fatal/emerg/segfault/oom-kill/out of memory) → `ERROR`
(error/failed/failure/denied/refused/cannot/unable/timeout) → `WARNING`
(warn/deprecated/retry/unreachable/invalid) → everything else is `INFO`.

**Measured false-positive rate:** on our generated corpus (730 parsed
lines across `auth.log` and `syslog`), every one of the 353 lines
classified `ERROR` and all 3 classified `CRITICAL` were genuine failed
logins / OOM kills — **0 false positives (0.0%)** against the planted
ground truth. That number is only honest for this dataset, though: the
rules are keyword matching, not semantic, so a real-world log with a
message like `sshd: reload after invalid config, retrying` would be
misclassified `WARNING` even though it may be routine. Keyword-based
severity is a defensible approximation, not a guarantee.

### First-seen / last-seen assumption

Syslog timestamps have no year. `AUTH` first/last-seen and the disk-space
projection's time span both assume the file is in chronological order —
"first line wins, every later line overwrites last" — rather than
reconstructing real dates. That is stated here as a documented design
decision rather than a silent bug.

### Burst detection

Averages over **hours that contain data**, not all 24 — a 3-hour log
would otherwise make every hour look like a 9x spike against a
mostly-empty 24-hour denominator. A burst is only reported when it clears
both a floor (≥10 events) and a multiple (≥3x the average), so a quiet
file with 2 errors in one hour and 1 in another does not print
"BURST DETECTED, 2x average."

### Self-designed feature 1 — Anomaly scoring (Zhillan)

Extends burst detection with `sum`/`sumsq` over active hours to compute
`mean`, `sd = sqrt(sumsq/active − mean²)`, and flags any hour where
`(x − mean) / sd ≥ k` (default `k = 2`, tunable with `--anomaly-k`). This
turns "that hour looks bad" into a defensible statistical claim, and
guards `sd == 0` so a perfectly flat log does not divide by zero.

### Self-designed feature 2 — Disk-space projection (Razzy)

**What it does.** For each source analysed, it takes the on-disk size of
the log (bytes) and the span the log itself covers (`META first`/`last`),
computes a bytes-per-hour growth rate, then checks that rate against the
*real* free space on the filesystem that holds the log (`df --output=avail
-B1`) to print, e.g., "`/var/log` fills in 6.2 days."

```
=== Disk-space projection ===
Growth rate : 2386.0 bytes/hour  (54877 bytes over a 23h span)
Free space  : 10720088064 bytes free on /tmp/logs
Projection  : /tmp/logs fills in 187204.7 days (~2539-04-08 08:08), at the observed rate.
```

**Why it matters.** Burst detection and anomaly scoring both answer "is
something unusual happening right now?" Neither answers the operational
question that actually pages someone at 3am: *at the current rate, when
does this partition run out of room?* A syslog on its own only tells you
how much data it produced over its own time span; it says nothing about
the disk it lives on. Joining those two numbers — the log's own growth
rate against `df`'s live free-space figure — is what turns "this log is
1.2 MB" into an actionable countdown, which is exactly the kind of number
that should trigger a rotation policy change *before* the disk fills, not
after.

**Design decisions and edge cases handled:**
- **Compressed sources use their on-disk (compressed) size**, not the
  decompressed content size — disk-space projection is about what is
  physically stored, so a `.gz` file's smaller footprint is the correct
  number to project from.
- **stdin and empty files have no meaningful byte count**, so the feature
  prints a one-line "skipping" note instead of a fabricated rate or a
  divide-by-zero.
- **Files with too little span data** (all lines unparsed, or a facts file
  with no `first`/`last`) get the same graceful skip rather than an error.
- **A log under an hour old** is clamped to a 1-hour span so a
  freshly-created file still gets a (rough, clearly short-window) rate
  instead of dividing by zero.
- **A rate of zero** (no bytes counted, or the math floors to 0.0) is
  reported as "never fills" instead of a bogus infinite ETA.
- **The year-boundary assumption** described above applies here too: if
  `last` parses to before `first`, one year is added to `last` before the
  span is computed.
- Uses `df --output=avail -B1` (bytes, not human-readable) so the
  projection math stays exact; the byte figures are printed alongside so
  the human-readable report is still self-explanatory.

**Known limitation:** the growth rate is a simple linear extrapolation
from the log's own span — it does not account for logs that grow in
bursts (e.g. the projection right after a `mklogs.sh`-generated burst hour
will over-estimate the "normal" rate). A production version would instead
sample `df`/file size at two points in time on a schedule and compute the
rate from that, rather than inferring it from one snapshot.

### Rotation engine

`app.log → app.log.1 → app.log.2[.gz] → … → deleted past --keep`. Dry run
by default; `--apply` required to touch anything; `assert_inside` is
called before every rename/delete so nothing outside the target directory
is ever touched, even via a crafted filename. Mode and owner are captured
*before* the rename (the original name no longer resolves afterward).

**Why the open-descriptor warning matters:** a process holds an open file
descriptor to the log's *inode*, not to its *name*. Renaming `app.log` to
`app.log.1` does not stop the writing process — its descriptor still
points at the same inode, so it keeps appending to the renamed file while
the newly-created `app.log` stays at zero bytes until the process is told
to reopen (`SIGHUP`, typically). `--copytruncate` avoids this by never
renaming — it copies the content out and truncates the original file
in place (same inode throughout), at the cost of a small window where
lines written between the copy and the truncate are lost.

## Known limitations

- Severity classification is keyword-based; see the measured caveat above.
- First-seen/last-seen and disk-space span both assume chronological,
  single-year-crossing-at-most log order rather than reconstructing full
  dates.
- Disk-space projection is a single-snapshot linear extrapolation, not a
  trend fit across multiple observations.
- Format auto-detection (syslog vs. Apache vs. JSON) was not attempted;
  the tool assumes syslog-format input throughout.
