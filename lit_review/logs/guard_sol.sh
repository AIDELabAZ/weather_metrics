#!/bin/bash
# Health guard for the full-corpus Sol run. Prints one line per event; stops
# the run if failures pile up (it resumes cleanly on relaunch).
L=/Users/kieran/Documents/GitHub/weather_metrics/lit_review/logs/full_baseline_sol.log
PAT="python3 -u baseline_sol.py"
seen_fail=$(grep -c '\[FAILED\]' "$L")
last_n=$(grep -c '^Final extracted' "$L"); last_t=$(date +%s)
stall_flag=0; quality_flag_at=0; tick=0
while true; do
  n=$(grep -c '^Final extracted' "$L"); now=$(date +%s)

  # New failures
  f=$(grep -c '\[FAILED\]' "$L")
  if [ "$f" -gt "$seen_fail" ]; then
    grep '\[FAILED\]' "$L" | tail -n $((f-seen_fail)) | cut -c1-250 | sed 's/^/FAILED: /'
    seen_fail=$f
  fi

  # Failure rate in the last 20 papers -> stop the run
  # (each paper logs one "Final extracted" line, plus one [FAILED] line if it failed)
  recent=$(grep -E '^Final extracted|\[FAILED\]' "$L" | tail -n 25 | grep -c '\[FAILED\]')
  if [ "$recent" -ge 5 ]; then
    pkill -f "$PAT"
    echo "STOPPED RUN: $recent failures among the last ~20 papers (at $n papers). Relaunch resumes."
    grep '\[FAILED\]' "$L" | tail -3 | cut -c1-250
    exit 0
  fi

  # Answer-quality checks over the last 20 papers (once per 20 papers)
  if [ "$n" -ge 20 ] && [ $((n - quality_flag_at)) -ge 20 ]; then
    win=$(grep -n '^Final extracted' "$L" | tail -n 20 | head -1 | cut -d: -f1)
    warns=$(tail -n +"$win" "$L" | grep -c '\[warn\]')
    emp1=$(grep '^Final extracted' "$L" | tail -n 20 | grep -c "'Empirical Analysis': '1'")
    if [ "$warns" -ge 5 ]; then echo "QUALITY: $warns truncated/empty-answer warnings in the last 20 papers (at $n)"; quality_flag_at=$n; fi
    if [ "$emp1" -eq 0 ]; then echo "QUALITY: none of the last 20 papers marked empirical (at $n) - possible garbage answers"; quality_flag_at=$n; fi
  fi

  # Stall
  if [ "$n" -gt "$last_n" ]; then last_n=$n; last_t=$now; stall_flag=0; fi
  if [ $((now-last_t)) -gt 600 ] && [ $stall_flag -eq 0 ]; then
    echo "STALL: no paper finished in 10 min (at $n papers)"; tail -2 "$L" | cut -c1-250; stall_flag=1
  fi

  # Exit
  if ! pgrep -f "$PAT" >/dev/null; then
    if grep -q '^Data saved to' "$L"; then
      echo "RUN FINISHED: $n papers, $f failed"
    else
      echo "RUN EXITED EARLY at $n papers"; tail -5 "$L" | cut -c1-250
    fi
    exit 0
  fi

  # Heartbeat every 30 min of checks
  tick=$((tick+1)); if [ $((tick % 29)) -eq 0 ]; then echo "OK: $n/3755 papers, $f failed"; fi
  sleep 60
done
