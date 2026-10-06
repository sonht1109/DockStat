#!/usr/bin/env bash
# CPU / RSS budget check for the running app.
#   ./Scripts/perf.sh [seconds]        (default 60)
#
# `ps -o %cpu` reports the average over the process's whole lifetime, which is
# dominated by launch, so the per-second figures come from `top` (which reports
# deltas) and the ps figures are printed only for the lifetime average.
set -uo pipefail

DURATION=${1:-60}
PID=$(pgrep -f 'DockStat.app/Contents/MacOS/dockstat' | head -1)

if [ -z "${PID}" ]; then
  echo "DockStat is not running. Start it with: make run"
  exit 1
fi

echo "sampling pid ${PID} for ${DURATION}s (app's own poll interval)"

tmp=$(mktemp)
trap 'rm -f "${tmp}"' EXIT

# top: first sample is "since boot" for the process, so it is dropped.
top -l "$((DURATION + 1))" -s 1 -pid "${PID}" -stats pid,cpu,mem 2>/dev/null \
  | awk -v pid="${PID}" '$1 == pid { gsub(/[+-]/, "", $3); print $2, $3 }' \
  | tail -n +2 >"${tmp}"

awk '
  { cpu += $1; mem += $2; n += 1
    if ($1 > cpuPeak) cpuPeak = $1
    if ($2 > memPeak) memPeak = $2
    if (n == 1) memFirst = $2
    memLast = $2 }
  END {
    if (n == 0) { print "no samples"; exit 1 }
    printf "samples       : %d\n", n
    printf "cpu mean      : %.2f %%   (per-second, one core = 100%%)\n", cpu / n
    printf "cpu peak      : %.2f %%\n", cpuPeak
    printf "footprint     : %.1f MB mean, %.1f MB peak, %+.1f MB drift\n", mem / n, memPeak, memLast - memFirst
  }
' "${tmp}"

echo "--- ps lifetime average (includes launch) ---"
ps -o %cpu=,rss= -p "${PID}" | awk '{ printf "cpu %s %%, rss %.1f MB\n", $1, $2 / 1024 }'
PID="${PID}" footprint -p "${PID}" 2>/dev/null | tail -2
