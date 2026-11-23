#!/usr/bin/env bash
# Probe (an-13), runs as root on a web VM: /etc/acme/settings.json is a JSON object, owned
# root:acme with mode 0640, with log_level = $1 (a string) and features.maintenance_page = false
# (a boolean), and without the key grader_probe (the grader's check-mode run must not have
# written it).
set -euo pipefail
f=/etc/acme/settings.json
[[ "$(stat -c '%a %U %G' "$f")" == "640 root acme" ]] || {
  echo "$f is $(stat -c '%a %U:%G' "$f"), want 640 root:acme"
  exit 1
}
python3 - "$f" "$1" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert isinstance(data, dict), "not a JSON object"
assert data.get("log_level") == sys.argv[2], "log_level is %r" % data.get("log_level")
assert data.get("features", {}).get("maintenance_page") is False, "features.maintenance_page is not false"
assert "grader_probe" not in data, "the check-mode run wrote grader_probe"
PY
