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
def git_source(r):
    # From an-14: the repo's own collection from git by tag,
    #   name: https://github.com/<owner>/<repo>.git#/<path>, type: git, version: <ns>.<name>-X.Y.Z
    # The collection's name comes from <path>/galaxy.yml in this repo (cwd is ansible/), else from
    # the tag; the version is the tag's X.Y.Z.
    import os, re
    url, _, frag = r["name"].partition("#")
    tag = str(r.get("version", ""))
    m = re.search(r"([0-9]+\.[0-9]+\.[0-9]+)$", tag)
    want = m.group(1) if m else tag
    gy = os.path.join("..", frag.strip("/"), "galaxy.yml")
    if frag and os.path.isfile(gy):
        meta = yaml.safe_load(open(gy))
        return f"{meta['namespace']}.{meta['name']}", want
    return re.sub(r"-[0-9][0-9.]*$", "", tag), want
for r in req:
    if isinstance(r, dict) and (r.get("type") == "git" or str(r.get("name", "")).startswith("git+")):
        name, want = git_source(r)
        if installed.get(name) != want:
            bad.append(f"{name}: pinned {r.get('version')}, installed {installed.get(name)}")
        continue
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
  # From an-14 the tree pins the repo's own collection (acme.platform) by git tag: those tags
  # must exist on GitHub before galaxy can clone them, and a moved tag must replace what is
  # installed (--force).
  if grep -qsE "github\.com/${GH_OWNER:?}/${LIVE_REPO:?}(\.git)?#" "$d/collections/requirements.yml"; then
    # shellcheck source=/dev/null
    source "$(dirname "$AN_PROBES")/collection-tag.sh"
    an_collection_tag_pinned || return 1
    (cd "$d" && .venv/bin/ansible-galaxy collection install --force -r collections/requirements.yml -p collections)
  else
    (cd "$d" && .venv/bin/ansible-galaxy collection install -r collections/requirements.yml -p collections)
  fi
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

# an_role_dir <role>: the directory of role <role>, relative to LIVE_DIR: ansible/roles/<role>
# until an-14, then roles/<role> of the collection under ansible/ (acme.platform, wherever its
# source lives). Prints nothing and fails when there is none.
an_role_dir() {
  local d
  if [[ -d "ansible/roles/$1" ]]; then
    echo "ansible/roles/$1"
    return 0
  fi
  d="$(find ansible \( -path ansible/.venv -o -path ansible/collections/ansible_collections -o -name .ansible -o -name molecule \) -prune \
    -o -type d -path "*/roles/$1" -print -quit 2>/dev/null)"
  [[ -n "$d" ]] && echo "$d"
}

# an_role_dirs: every role directory under ansible/ (ansible/roles/* and the roles of a collection
# source), installed collections and the venv excluded. One path per line.
an_role_dirs() {
  local r d
  while IFS= read -r r; do
    for d in "$r"/*/; do
      [[ -d "$d" ]] && echo "${d%/}"
    done
  done < <(find ansible \( -path ansible/.venv -o -path ansible/collections/ansible_collections -o -name .ansible -o -name molecule \) -prune \
    -o -type d -name roles -print 2>/dev/null)
  return 0
}

# an_module_file <name>: the Python file of custom module <name> under ansible/: ansible/library
# (an-13) or a collection's plugins/modules (an-14). Prints it; fails when there is none.
an_module_file() {
  local f
  f="$(find ansible \( -path ansible/.venv -o -path ansible/collections/ansible_collections -o -name .ansible \) -prune \
    -o -type f -name "$1.py" \( -path "*/library/*" -o -path "*/plugins/modules/*" \) -print -quit 2>/dev/null)"
  [[ -n "$f" ]] && echo "$f"
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
  local group=$1 f r
  # The role by name or, from an-14, by its collection FQCN (acme.platform.<role>).
  r="([a-z0-9_]+\.[a-z0-9_]+\.)?$2"
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
  local d f
  d="$(an_role_dir "$1")/molecule/default"
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
  local venv="$PWD/ansible/.venv" d
  [[ -f "$venv/bin/activate" ]] || return 3
  d="$(an_role_dir "$1")" && [[ -n "$d" ]] || return 1
  (
    cd "$d" || exit 1
    # shellcheck disable=SC1091
    source "$venv/bin/activate"
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

# ---- phase C: delegation, the collection acme.platform ------------------------------------

# an_delegates_to <playbook> <group>: a delegate_to: line of the playbook names the inventory
# group <group>, directly (groups['role_jump'] | first) or through a variable whose definition (in the
# playbook or the inventory's group variables) does. Never a host name or an IP.
an_delegates_to() {
  local f=$1 g=$2 line v
  while IFS= read -r line; do
    [[ "$line" == *"$g"* ]] && return 0
    v="$(sed -nE 's/.*\{\{-?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*-?\}\}.*/\1/p' <<<"$line")"
    [[ -n "$v" ]] || continue
    grep -rqsE "^[[:space:]]*$v:.*$g" "$f" ansible/inventory ansible/group_vars && return 0
  done < <(grep -E "^[[:space:]]*delegate_to:" "$f")
  return 1
}

# an_coll_dir: the collection's source directory (the one whose galaxy.yml says acme / platform),
# relative to LIVE_DIR.
an_coll_dir() {
  local g
  while IFS= read -r g; do
    grep -qE "^namespace:[[:space:]]*.?acme.?[[:space:]]*$" "$g" && grep -qE "^name:[[:space:]]*.?platform.?[[:space:]]*$" "$g" &&
      { dirname "$g"; return 0; }
  done < <(find ansible \( -path ansible/.venv -o -path ansible/collections/ansible_collections -o -name .ansible \) -prune \
    -o -type f -name galaxy.yml -print 2>/dev/null)
  return 1
}

# an_coll_pin: requirements.yml installs the collection from this repo's git URL, the #/ fragment
# being the collection's directory, type git, version a tag acme.platform-X.Y.Z. Prints the tag.
an_coll_pin() {
  local d f=ansible/collections/requirements.yml
  d="$(an_coll_dir)" || return 1
  awk -v url="github.com/$GH_OWNER/$LIVE_REPO" -v frag="#/$d" '
    function done_item() { if (own && git && tag != "") { print tag; found = 1; exit } }
    /^[[:space:]]*-[[:space:]]/ { done_item(); own = 0; git = 0; tag = "" }
    { line = $0; sub(/[[:space:]]*#[^\/].*$/, "", line) }
    index(line, url) && (index(line, frag "\"") || index(line, frag "/") || index(line, frag "\047") || line ~ (frag "[[:space:]]*$")) { own = 1 }
    line ~ /type:[[:space:]]*.?git/ { git = 1 }
    line ~ /version:[[:space:]]*.?acme\.platform-[0-9]+\.[0-9]+\.[0-9]+/ { tag = line; sub(/.*version:[[:space:]]*/, "", tag); gsub(/["\047[:space:]]/, "", tag) }
    END { if (!found) { done_item() } ; exit !found }
  ' "$f"
}

# ---- phase C: the Ansible workflow (an-16 …) -------------------------------------------------

export AN_WF=.github/workflows/ansible.yml

# an_wf_jobs [file]: the job ids directly under jobs: of the workflow, one per line.
an_wf_jobs() {
  local f=${1:-$AN_WF}
  [[ -f "$f" ]] || return 1
  awk '/^jobs:/ { j = 1; next } j && /^[^[:space:]#]/ { j = 0 }
    j && /^[[:space:]]+[A-Za-z0-9_-]+:/ { n = match($0, /[^[:space:]]/) - 1; if (!ind) ind = n
      if (n == ind) { k = $0; sub(/^[[:space:]]+/, "", k); sub(/:.*/, "", k); print k } }' "$f"
}

# an_wf_job <job> [file]: the lines of that job, comments dropped.
an_wf_job() {
  local f=${2:-$AN_WF}
  [[ -f "$f" ]] || return 1
  awk -v want="$1" '/^[[:space:]]*#/ { next } /^jobs:/ { j = 1; next } j && /^[^[:space:]#]/ { j = 0 }
    j && /^[[:space:]]+[A-Za-z0-9_-]+:/ { n = match($0, /[^[:space:]]/) - 1; if (!ind) ind = n
      if (n == ind) { k = $0; sub(/^[[:space:]]+/, "", k); sub(/:.*/, "", k); cur = k } }
    j && cur == want { print }' "$f"
}

# an_wf_self_hosted <job> [file]: the job runs on the self-hosted runner (runs-on names
# self-hosted and acme-jump, in a list on one line or as list items).
an_wf_self_hosted() {
  local body
  body="$(an_wf_job "$1" "${2:-$AN_WF}")" || return 1
  grep -qE "runs-on:.*self-hosted|^[[:space:]]*-[[:space:]]*.?self-hosted" <<<"$body" &&
    grep -qE "acme-jump" <<<"$body"
}

# an_wf_runner_jobs [file]: the ids of the jobs that run on the self-hosted runner.
an_wf_runner_jobs() {
  local j
  while IFS= read -r j; do
    an_wf_self_hosted "$j" "${1:-$AN_WF}" && echo "$j"
  done < <(an_wf_jobs "${1:-$AN_WF}")
  return 0
}

# an_wf_job_if <job> [file]: the job's own if: expression (not a step's), without ${{ }} and
# surrounding double quotes. Empty when the job has none.
an_wf_job_if() {
  local body ind
  body="$(an_wf_job "$1" "${2:-$AN_WF}")" || return 1
  ind="$(awk 'NR > 1 && NF { match($0, /[^ ]/); print substr($0, 1, RSTART - 1); exit }' <<<"$body")"
  [[ -n "$ind" ]] || return 0
  sed -n "s/^${ind}if:[[:space:]]*//p" <<<"$body" | head -n1 |
    sed -E 's/[[:space:]]+$//; s/^"(.*)"$/\1/; s/^\$\{\{[[:space:]]*//; s/[[:space:]]*\}\}$//'
}

# an_wf_guard_ok <expression>: the expression keeps fork pull requests out. The fork guard is
# head.repo.full_name == github.repository (either way round), alone or as the PR-only clause
# (github.event_name != 'pull_request' || <guard>). It must be AND-ed in at every level: never
# OR-ed with anything (always() || <guard> runs every fork), never negated.
an_wf_guard_ok() {
  local e=$1 prev guard pr
  guard='[[:alnum:]_.]*head\.repo\.full_name[[:space:]]*==[[:space:]]*github\.repository|github\.repository[[:space:]]*==[[:space:]]*[[:alnum:]_.]*head\.repo\.full_name'
  pr="github\.event_name[[:space:]]*!=[[:space:]]*'pull_request'"
  e="$(sed -E "s/$guard/@/g" <<<"$e")"
  # github.repository_owner and the like are not the guard
  ! grep -qE '@[[:alnum:]_.]' <<<"$e" || return 1
  e="$(sed -E "s/^[[:space:]]*${pr}[[:space:]]*\|\|[[:space:]]*@[[:space:]]*\$/@/; s/\([[:space:]]*${pr}[[:space:]]*\|\|[[:space:]]*@[[:space:]]*\)/@/g; s/\([[:space:]]*@[[:space:]]*\|\|[[:space:]]*${pr}[[:space:]]*\)/@/g" <<<"$e")"
  # fold every parenthesised group without the guard (and "( @ )") until nothing changes: what is
  # left are the guard and the operators on its path to the top
  prev=""
  while [[ "$e" != "$prev" ]]; do
    prev=$e
    e="$(sed -E 's/\([^()@]*\)/X/g; s/\([[:space:]]*@[[:space:]]*\)/@/g' <<<"$e")"
  done
  [[ "$e" == *@* && "$e" != *"||"* ]] && ! grep -qE '![[:space:]]*[(@]' <<<"$e"
}

# an_wf_fork_guard <job> [file]: the job's own if: keeps fork pull requests away from the runner
# (an_wf_guard_ok).
an_wf_fork_guard() {
  local e
  e="$(an_wf_job_if "$1" "${2:-$AN_WF}")" || return 1
  [[ -n "$e" ]] && an_wf_guard_ok "$e"
}

# an_wf_run_jobs <repo> <run id>: the run's jobs as JSON lines {name, conclusion, labels}.
an_wf_run_jobs() {
  gh api "repos/$1/actions/runs/$2/jobs?per_page=100" --jq '.jobs[] | {name, conclusion, labels}'
}

# an_wf_job_succeeded <repo> <run query> <job name> <self-hosted:0|1>: one of the newest 20
# completed runs of ansible.yml matching <run query> (e.g. "event=push&branch=main") has a job
# named <job name> that succeeded (and ran on acme-jump, if asked).
an_wf_job_succeeded() {
  local repo=$1 q=$2 job=$3 sh=$4 id
  for id in $(gh api "repos/$repo/actions/workflows/ansible.yml/runs?status=completed&per_page=20&$q" --jq '.workflow_runs[].id'); do
    an_wf_run_jobs "$repo" "$id" | jq -se --arg n "$job" --argjson sh "$sh" \
      'any(.[]; (.name == $n or (.name | startswith($n + " ("))) and .conclusion == "success" and ($sh == 0 or (.labels | index("acme-jump") != null)))' >/dev/null && return 0
  done
  return 1
}

export -f an_run an_host_count an_on_all an_recap_clean an_second_run an_collection_pinned \
  an_first_file an_precommit_config an_collections_match an_count an_probe an_playbooks \
  an_play_applies an_molecule_scenario an_group_ips an_hostvar an_molecule_test an_kv_name \
  an_role_dir an_role_dirs an_module_file an_delegates_to an_coll_dir an_coll_pin \
  an_wf_jobs an_wf_job an_wf_self_hosted an_wf_runner_jobs an_wf_job_if an_wf_guard_ok an_wf_fork_guard \
  an_wf_run_jobs an_wf_job_succeeded
