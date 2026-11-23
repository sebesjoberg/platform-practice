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

# ---- phase B: probes, Molecule, Key Vault prerequisites ------------------------------------

# Absolute path of the probe scripts (tracks/ansible/lib/probes): checks copy them to the VMs with
# the script module, which needs a path that works from ansible/.
AN_PROBES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/probes"
export AN_PROBES

# an_count <pattern>: number of inventory hosts matching <pattern>.
an_count() {
  an_run ansible "$1" --list-hosts 2>/dev/null | sed -nE 's/^[[:space:]]*hosts \(([0-9]+)\):.*/\1/p' | head -n1
}

# an_probe <pattern> <min-hosts> <probe> [args...]: run tracks/ansible/lib/probes/<probe> as root
# on every host of <pattern> through the learner's inventory. Succeeds only when the pattern
# matches at least <min-hosts> hosts and the probe exits 0 on each of them. Read-only probes.
an_probe() {
  local pattern=$1 min=$2 probe=$3 n
  shift 3
  n="$(an_count "$pattern")"
  [[ "${n:-0}" -ge "$min" ]] || return 1
  an_run ansible "$pattern" -b -m ansible.builtin.script -a "$AN_PROBES/$probe $*"
}

# an_playbooks: the playbook files under ansible/: site.yml, other top-level *.yml (imported from
# site.yml) and ansible/playbooks/*.yml. One path per line.
an_playbooks() {
  local f
  for f in ansible/*.yml ansible/*.yaml ansible/playbooks/*.yml ansible/playbooks/*.yaml; do
    [[ -f "$f" ]] && echo "$f"
  done
  return 0
}

# an_play_applies <group> <role>: a playbook has a play for hosts: <group> and applies role <role>
# (`- role: x`, `- x`, `roles: [x]`, `- { role: x }`, or import_role/include_role name: x).
an_play_applies() {
  local group=$1 r=$2 f
  while IFS= read -r f; do
    grep -qE "hosts:[[:space:]]*.?$group.?[[:space:]]*$" "$f" || continue
    grep -qE "^[[:space:]]*-[[:space:]]*.?$r.?[[:space:]]*$|role:[[:space:]]*.?$r([^[:alnum:]_.-]|$)|roles:[[:space:]]*\[([^]]*[[:space:],])?.?$r.?([[:space:],]|\])" "$f" && return 0
    grep -qE "(import|include)_role:" "$f" && grep -qE "^[[:space:]]*name:[[:space:]]*.?$r.?[[:space:]]*$" "$f" && return 0
  done < <(an_playbooks)
  return 1
}

# an_molecule_scenario <role>: roles/<role>/molecule/default has the docker driver, a converge and
# a verify playbook, no testinfra, and a custom test_sequence (if any) keeps idempotence and verify.
an_molecule_scenario() {
  local d="ansible/roles/$1/molecule/default" f
  f="$d/molecule.yml"
  [[ -f "$f" ]] && grep -qE "^driver:" "$f" && grep -qE "^[[:space:]]+name:[[:space:]]*.?docker.?[[:space:]]*$" "$f" || return 1
  compgen -G "$d/converge.y*ml" >/dev/null && compgen -G "$d/verify.y*ml" >/dev/null || return 1
  ! grep -qE "^[[:space:]]+name:[[:space:]]*.?testinfra" "$f" || return 1
  ! grep -qE "^[[:space:]]*test_sequence:" "$f" || { grep -qE "^[[:space:]]*-[[:space:]]*idempotence" "$f" && grep -qE "^[[:space:]]*-[[:space:]]*verify" "$f"; }
}

# an_group_ips <group>: the first private IP of every host in <group>, one per line (from the
# azure_rm host variable private_ipv4_addresses).
an_group_ips() {
  an_run ansible-inventory --list | jq -r --arg g "$1" \
    '. as $all | ($all[$g].hosts // [])[] | $all._meta.hostvars[.].private_ipv4_addresses[0] // empty'
}

# an_hostvar <host> <var>: the value of <var> for <host> as Ansible resolves it (debug runs on the
# control node; nothing connects to the VM). Plain strings only.
an_hostvar() {
  ANSIBLE_CALLBACK_RESULT_FORMAT=json an_run ansible "$1" -m ansible.builtin.debug -a "var=$2" |
    sed -nE "s/^[[:space:]]*\"$2\":[[:space:]]*\"([^\"]*)\",?[[:space:]]*\$/\\1/p" | head -n1
}

# an_molecule_test <role>: molecule test for ansible/roles/<role>, venv active, plain output.
an_molecule_test() {
  [[ -f ansible/.venv/bin/activate ]] || return 3
  (
    cd "ansible/roles/$1" || exit 1
    # shellcheck disable=SC1091
    source ../../.venv/bin/activate
    env ANSIBLE_NOCOLOR=1 ANSIBLE_FORCE_COLOR=0 PY_COLORS=0 molecule test
  )
}

# an_kv_name: the dev Key Vault (tf-21).
an_kv_name() {
  printf 'kv-%s-dev-%s\n' "${PREFIX:?}" "${SUFFIX:?}"
}

# an_az_retry <tries> <seconds> <cmd...>: run an az command, retrying while Azure answers 403. A
# role assignment needs a few minutes to reach the Key Vault data plane.
an_az_retry() {
  local tries=$1 wait=$2 i rc=1 err
  shift 2
  err="$(mktemp)"
  for ((i = 1; i <= tries; i++)); do
    "$@" 2>"$err" && {
      rm -f "$err"
      return 0
    }
    rc=$?
    grep -qiE "forbidden|not authorized|authorizationfailed" "$err" || break
    [[ $i -lt $tries ]] && sleep "$wait"
  done
  cat "$err" >&2
  rm -f "$err"
  return "$rc"
}

# an_kv_count <kind> <vault> <name> [list-args...]: how many objects named <name> `az keyvault
# <kind> list` (or list-deleted, via the extra args) returns: 0 or 1. Fails, printing nothing,
# when the listing fails: callers must never take a failed listing for "not there" and create (a
# new secret version overwrites the value; a new certificate version changes the thumbprint).
# 403s right after a role assignment are retried for up to 10 minutes.
an_kv_count() {
  local kind=$1 kv=$2 name=$3 n
  shift 3
  n="$(an_az_retry 20 30 az keyvault "$kind" "${@:-list}" --vault-name "$kv" --query "length([?name=='$name'])" -o tsv)" || return 1
  [[ "$n" =~ ^[01]$ ]] || return 1
  echo "$n"
}

# an_kv_secret_ensure (an-07's prerequisite): secret app-greeting in the dev vault, with a random
# value. Never overwrites an existing value; recovers a soft-deleted one. Records the value in
# $LAB_HOME/snapshots/an-07.value (mode 0600) for the grader. Runs as you (az login): tf-21 made
# you Key Vault Secrets Officer on the subscription. Returns 1 on any Azure error, having created
# nothing it couldn't prove was missing.
an_kv_secret_ensure() {
  local kv snap v tmp n
  kv="$(an_kv_name)"
  snap="${LAB_HOME:?}/snapshots/an-07.value"
  az keyvault show -n "$kv" --query id -o tsv >/dev/null || {
    echo "an-07: Key Vault $kv not found: the tf-25 state is missing (./lab.sh resume, or ./lab.sh catchup tf-25)" >&2
    return 1
  }
  n="$(an_kv_count secret "$kv" app-greeting list)" || {
    echo "an-07: cannot list the secrets of $kv; nothing changed" >&2
    return 1
  }
  if [[ "$n" == 1 ]]; then
    echo "an-07: secret app-greeting already in $kv (kept)"
  else
    n="$(an_kv_count secret "$kv" app-greeting list-deleted)" || {
      echo "an-07: cannot list the deleted secrets of $kv; nothing changed" >&2
      return 1
    }
    if [[ "$n" == 1 ]]; then
      az keyvault secret recover --vault-name "$kv" -n app-greeting -o none || return 1
      an_az_retry 12 5 az keyvault secret show --vault-name "$kv" -n app-greeting --query id -o none || return 1
      echo "an-07: recovered the deleted secret app-greeting in $kv"
    else
      v="$(python3 -c 'import secrets; print(secrets.token_hex(16))')" || return 1
      tmp="$(mktemp)"
      chmod 600 "$tmp"
      printf '%s' "$v" >"$tmp"
      # --file keeps the value off the command line (and out of the process list).
      if ! az keyvault secret set --vault-name "$kv" -n app-greeting --file "$tmp" --encoding utf-8 \
        --content-type text/plain -o none; then
        rm -f "$tmp"
        return 1
      fi
      rm -f "$tmp"
      echo "an-07: the app team stored the secret app-greeting in $kv"
    fi
  fi
  v="$(az keyvault secret show --vault-name "$kv" -n app-greeting --query value -o tsv)" || return 1
  [[ -n "$v" ]] || return 1
  mkdir -p "$LAB_HOME/snapshots"
  (umask 077 && printf '%s\n' "$v" >"$snap")
}

# an_kv_cert_policy <file>: write the Key Vault certificate policy of web-tls: self-signed,
# CN=acme-web.internal, SANs for the name and both web VMs, 12 months, PEM (key + certificate in
# the certificate's secret), renewed by Key Vault 30 days before expiry.
an_kv_cert_policy() {
  cat >"$1" <<EOF
{
  "issuerParameters": { "name": "Self" },
  "keyProperties": { "exportable": true, "keyType": "RSA", "keySize": 2048, "reuseKey": false },
  "secretProperties": { "contentType": "application/x-pem-file" },
  "x509CertificateProperties": {
    "subject": "CN=acme-web.internal",
    "subjectAlternativeNames": {
      "dnsNames": ["acme-web.internal", "vm-${PREFIX:?}-web-dev-1", "vm-${PREFIX:?}-web-dev-2"]
    },
    "keyUsage": ["digitalSignature", "keyEncipherment"],
    "ekus": ["1.3.6.1.5.5.7.3.1"],
    "validityInMonths": 12
  },
  "lifetimeActions": [
    { "trigger": { "daysBeforeExpiry": 30 }, "action": { "actionType": "AutoRenew" } }
  ]
}
EOF
}

# an_kv_cert_ensure (an-08's prerequisite): you get Key Vault Certificates Officer on the dev vault
# (the platform team's grant, by az: no Terraform change), and the vault gets the self-signed
# certificate web-tls. Never creates a new version of an existing certificate (that would change
# the thumbprint): a listing that fails stops here, a soft-deleted certificate is recovered, a
# pending first version is waited for. Returns 1 on any Azure error.
an_kv_cert_ensure() {
  local kv id me ra pol tp n i
  kv="$(an_kv_name)"
  id="$(az keyvault show -n "$kv" --query id -o tsv)" && [[ -n "$id" ]] || {
    echo "an-08: Key Vault $kv not found: the tf-25 state is missing (./lab.sh resume, or ./lab.sh catchup tf-25)" >&2
    return 1
  }
  me="$(az ad signed-in-user show --query id -o tsv)" && [[ -n "$me" ]] || return 1
  ra="$(az role assignment list --assignee "$me" --scope "$id" --role "Key Vault Certificates Officer" --query "[0].id" -o tsv)" || return 1
  if [[ -z "$ra" ]]; then
    az role assignment create --assignee-object-id "$me" --assignee-principal-type User \
      --role "Key Vault Certificates Officer" --scope "$id" -o none || return 1
    echo "an-08: the platform team granted you Key Vault Certificates Officer on $kv"
  fi
  # Pending (not yet issued) certificates count as existing.
  n="$(an_kv_count certificate "$kv" web-tls list --include-pending true)" || {
    echo "an-08: cannot list the certificates of $kv; nothing created" >&2
    return 1
  }
  if [[ "$n" == 1 ]]; then
    echo "an-08: certificate web-tls already in $kv (kept)"
  else
    n="$(an_kv_count certificate "$kv" web-tls list-deleted)" || {
      echo "an-08: cannot list the deleted certificates of $kv; nothing created" >&2
      return 1
    }
    if [[ "$n" == 1 ]]; then
      az keyvault certificate recover --vault-name "$kv" -n web-tls -o none || return 1
      echo "an-08: recovered the deleted certificate web-tls in $kv"
    else
      pol="$(mktemp)"
      an_kv_cert_policy "$pol"
      if ! an_az_retry 20 30 az keyvault certificate create --vault-name "$kv" -n web-tls --policy "@$pol" -o none; then
        rm -f "$pol"
        return 1
      fi
      rm -f "$pol"
      echo "an-08: the platform team created the self-signed certificate web-tls in $kv"
    fi
  fi
  # A new, recovered or pending certificate: wait until it is issued (it has a thumbprint).
  for ((i = 0; i < 30; i++)); do
    tp="$(az keyvault certificate show --vault-name "$kv" -n web-tls --query x509ThumbprintHex -o tsv 2>/dev/null || true)"
    [[ -n "$tp" ]] && return 0
    sleep 5
  done
  echo "an-08: certificate web-tls in $kv was not issued within 150 s (az keyvault certificate pending show --vault-name $kv -n web-tls)" >&2
  return 1
}

# an_tree_uses <text>: <text> occurs in a file under $LIVE_DIR/ansible.
an_tree_uses() {
  grep -rqsF --exclude-dir=.venv --exclude-dir=collections --exclude-dir=.ansible -- "$1" "${LIVE_DIR:?}/ansible"
}

# an_task_started <id>: <id> has a row in $LAB_HOME/progress (./lab.sh next started it).
an_task_started() {
  [[ -f "${LAB_HOME:?}/progress" ]] && awk -F'\t' -v id="$1" '$1 == id { f = 1 } END { exit !f }' "$LAB_HOME/progress"
}

# an_kv_prereqs: put back the Key Vault objects the playbooks need: an-07's secret and an-08's
# certificate, each once the task was started or the repo uses it. They live in the dev vault,
# which ./lab.sh pause destroys and resume recreates empty.
an_kv_prereqs() {
  if an_tree_uses app-greeting || an_task_started an-07; then
    an_kv_secret_ensure || return 1
  fi
  if an_tree_uses web-tls || an_task_started an-08; then
    an_kv_cert_ensure || return 1
  fi
}

# an_catchup_converge: (catchup) apply the caught-up tree once: Key Vault prerequisites first
# (the hooks of an-07/an-08 run after an-03's), then site.yml.
an_catchup_converge() {
  an_kv_prereqs || return 1
  an_run ansible-playbook site.yml
}

export -f an_run an_host_count an_on_all an_recap_clean an_second_run an_collection_pinned \
  an_first_file an_precommit_config an_collections_match an_count an_probe an_playbooks \
  an_play_applies an_molecule_scenario an_group_ips an_hostvar an_molecule_test an_kv_name
