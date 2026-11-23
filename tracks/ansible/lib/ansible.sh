# shellcheck shell=bash
# Helpers shared by the ansible track's checks.sh and catchup.sh files (cwd = LIVE_DIR).
# checks.sh sources this file; the functions are exported so that check commands (run with
# `bash -o pipefail -c`) can call them.
#
# The learner's Ansible lives in $LIVE_DIR/ansible with its own virtualenv ansible/.venv
# (gitignored, built from ansible/requirements.txt) and collections installed into
# ansible/collections (gitignored, from ansible/collections/requirements.yml).

# an_run <cmd...>: run <cmd> from ansible/ with ansible/.venv active and ansible/ansible.cfg in
# force (explicitly, so a world-writable checkout can't make Ansible ignore it). Plain output:
# no colour, the default stdout callback (its PLAY RECAP format is what the checks parse).
# Returns 3 without a venv.
an_run() {
  if [[ ! -f ansible/.venv/bin/activate ]]; then
    echo "no ansible/.venv: python3 -m venv ansible/.venv && ansible/.venv/bin/pip install -r ansible/requirements.txt" >&2
    return 3
  fi
  (
    cd ansible || exit 1
    # shellcheck disable=SC1091
    source .venv/bin/activate
    export ANSIBLE_CONFIG="$PWD/ansible.cfg" ANSIBLE_NOCOLOR=1 ANSIBLE_FORCE_COLOR=0
    export ANSIBLE_STDOUT_CALLBACK=ansible.builtin.default
    "$@"
  )
}

# an_host_count: number of hosts the inventory resolves for `all`.
an_host_count() {
  an_run ansible all --list-hosts 2>/dev/null | sed -nE 's/^[[:space:]]*hosts \(([0-9]+)\):.*/\1/p' | head -n1
}

# an_on_all <shell command>: run <command> as root on every inventory host; succeeds only when
# the inventory has at least the three lab VMs and the command succeeds on each of them.
an_on_all() {
  local n
  n="$(an_host_count)"
  [[ "${n:-0}" -ge 3 ]] || return 1
  an_run ansible all -b -m ansible.builtin.shell -a "$1"
}

# an_recap_clean <file>: the PLAY RECAP in <file> lists at least 3 hosts, every one of them with
# changed=0, unreachable=0 and failed=0.
an_recap_clean() {
  awk '
    /^PLAY RECAP/ { on = 1; next }
    on && / : ok=[0-9]+/ {
      n++
      if ($0 !~ /[[:space:]]changed=0[[:space:]]/ || $0 !~ /[[:space:]]unreachable=0[[:space:]]/ || $0 !~ /[[:space:]]failed=0[[:space:]]/) bad++
    }
    END { exit !(n >= 3 && bad == 0) }
  ' "$1"
}

# an_second_run: run site.yml (against a converged fleet it changes nothing) and require a clean
# recap. Prints the recap so the learner can compare.
an_second_run() {
  local log rc=0
  log="$(mktemp)"
  an_run ansible-playbook site.yml >"$log" 2>&1 || rc=$?
  sed -n '/^PLAY RECAP/,$p' "$log"
  if [[ $rc -eq 0 ]] && an_recap_clean "$log"; then rc=0; else rc=1; fi
  rm -f "$log"
  return "$rc"
}

# an_collection_pinned <requirements.yml> <name>: <name> is listed with an exact version
# (X.Y.Z or ==X.Y.Z), block style (name: on one line, version: on a later line of the same
# item) or flow style ({name: ..., version: ...}).
an_collection_pinned() {
  awk -v want="$2" '
    function strip(s) { gsub(/["\047]/, "", s); return s }
    /^[[:space:]]*-[[:space:]]/ { cur = "" }
    {
      line = $0
      if (match(line, /name:[[:space:]]*["\047]?[A-Za-z0-9_.]+/)) {
        v = substr(line, RSTART, RLENGTH); sub(/name:[[:space:]]*/, "", v); cur = strip(v)
      }
      if (cur == want && line ~ /version:[[:space:]]*["\047]?(==)?[0-9]+\.[0-9]+\.[0-9]+["\047]?[[:space:]]*([,}#].*)?$/) found = 1
    }
    END { exit !found }
  ' "$1"
}

# an_first_file <path>...: print the first path that exists; fail when none does.
an_first_file() {
  local f
  for f in "$@"; do
    if [[ -f "$f" ]]; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

# an_precommit_config: the repo's pre-commit config (ansible/ or the repo root).
an_precommit_config() {
  an_first_file ansible/.pre-commit-config.yaml ansible/.pre-commit-config.yml .pre-commit-config.yaml .pre-commit-config.yml
}

# an_collections_match: every collection pinned in collections/requirements.yml is installed in
# exactly that version, as Ansible resolves it with ansible.cfg (first match on the path wins).
an_collections_match() {
  an_run python3 - <<'PY'
import json, subprocess, sys
import yaml
req = yaml.safe_load(open("collections/requirements.yml"))["collections"]
out = subprocess.run(["ansible-galaxy", "collection", "list", "--format", "json"],
                     capture_output=True, text=True, check=True).stdout
installed = {}
for _path, cols in json.loads(out).items():
    for name, meta in cols.items():
        installed.setdefault(name, meta.get("version"))
bad = []
for r in req:
    name = r["name"] if isinstance(r, dict) else r
    want = str(r.get("version", "")).lstrip("=") if isinstance(r, dict) else ""
    if installed.get(name) != want:
        bad.append(f"{name}: pinned {want or '(no version)'}, installed {installed.get(name)}")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
}

# an_venv_sync: (catchup) create ansible/.venv if missing and install everything the pinned
# files ask for: requirements.txt, the collections, and the Azure collection's Python packages.
an_venv_sync() {
  local d="$LIVE_DIR/ansible" az
  [[ -f "$d/requirements.txt" ]] || { echo "no $d/requirements.txt" >&2; return 1; }
  [[ -x "$d/.venv/bin/python" ]] || python3 -m venv "$d/.venv"
  "$d/.venv/bin/pip" install -q --upgrade pip
  "$d/.venv/bin/pip" install -q -r "$d/requirements.txt"
  (cd "$d" && .venv/bin/ansible-galaxy collection install -r collections/requirements.yml -p collections)
  az="$d/collections/ansible_collections/azure/azcollection/requirements.txt"
  if [[ -f "$az" ]]; then
    "$d/.venv/bin/pip" install -q -r "$az"
  fi
}

export -f an_run an_host_count an_on_all an_recap_clean an_second_run an_collection_pinned \
  an_first_file an_precommit_config an_collections_match
