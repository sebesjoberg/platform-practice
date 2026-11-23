#!/usr/bin/env bash
# Probe (an-11, an-18), runs as root on the jump host: a request loop against HAProxy on
# 127.0.0.1:80, one request every 0.2 s, while the grader rolls a release out.
#   start <id> <seconds>  start the loop detached and return. It ends by itself after <seconds>
#                         (timeout), so it never outlives the grader's check even when the
#                         grader is killed.
#   stop <id>             stop the loop, print the counts, remove its files; exit 0 only when it
#                         made at least 25 requests and every one of them answered 200.
# Read-only for the system: it only writes /run/acme-grader/<id>.{pid,log}.
set -euo pipefail
cmd=${1:?start|stop}
id=${2:?id}
dir=/run/acme-grader
pidf="$dir/$id.pid"
log="$dir/$id.log"

stop_loop() {
  local pid
  [[ -s "$pidf" ]] || return 0
  pid="$(cat "$pidf")"
  # The loop runs in its own session (setsid): its pid is the process group of the loop, curl
  # and sleep included.
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  kill -KILL -- "-$pid" 2>/dev/null || true
  rm -f "$pidf"
}

case "$cmd" in
  start)
    secs=${3:?seconds}
    mkdir -p "$dir"
    chmod 700 "$dir"
    stop_loop
    : >"$log"
    # One line per request: the HTTP status, 000 when curl got no answer (refused, timeout).
    setsid timeout "$secs" bash -c '
      while :; do
        code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1/ || true)"
        echo "${code:-000}" >>"$1"
        sleep 0.2
      done' loop "$log" </dev/null >/dev/null 2>&1 &
    echo "$!" >"$pidf"
    echo "load loop started (pid $!, at most ${secs}s)"
    ;;
  stop)
    stop_loop
    total=0 failed=0
    if [[ -f "$log" ]]; then
      total="$(grep -c . "$log" || true)"
      failed="$(grep -vcx 200 "$log" || true)"
      if [[ "$failed" -gt 0 ]]; then
        echo "answers other than 200: $(grep -vx 200 "$log" | sort | uniq -c | tr -s ' ' | paste -sd, -)"
      fi
      rm -f "$log"
    fi
    echo "requests: $total, failed: $failed"
    [[ "$total" -ge 25 && "$failed" -eq 0 ]]
    ;;
  *)
    echo "usage: $0 start <id> <seconds> | stop <id>" >&2
    exit 2
    ;;
esac
