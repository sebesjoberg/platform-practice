#!/usr/bin/env bash
# Validate the reference state of a task without Azure:
#   tests/validate-reference.sh <id> [--no-molecule]
# Honours TRACKS_DIR (default <repo>/tracks). Renders with the fixture config, then runs, for
# every terraform dir (stacks and modules): fmt, init -backend=false, validate, tflint, trivy,
# terraform test; and for ansible/: yamllint, ansible-lint, syntax-check, molecule.
# Prints a per-step summary; exits non-zero on the first failing step (after its output).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TRACKS_DIR="${TRACKS_DIR:-$REPO/tracks}"
# shellcheck source=lib/common.sh
source "$REPO/lib/common.sh"
# shellcheck source=lib/tasks.sh
source "$REPO/lib/tasks.sh"
# shellcheck source=lib/template.sh
source "$REPO/lib/template.sh"
# shellcheck source=lib/catchup.sh
source "$REPO/lib/catchup.sh"
# shellcheck source=lib/selftest.sh
source "$REPO/lib/selftest.sh"

id="" molecule=1
for a in "$@"; do
  case "$a" in
    --no-molecule) molecule=0 ;;
    -*) die 2 "unknown option $a" ;;
    *) id=$a ;;
  esac
done
[[ -n "$id" ]] || die 2 "usage: tests/validate-reference.sh <id> [--no-molecule]"

export PATH="$HOME/.local/bin:$PATH"
VENV="$HOME/.local/share/platform-practice/venv"
# shellcheck disable=SC1091
[[ -f "$VENV/bin/activate" ]] && source "$VENV/bin/activate"
# Test hook: a directory of shim executables that takes priority over the real tools.
[[ -z "${VALIDATE_SHIM_DIR:-}" ]] || export PATH="$VALIDATE_SHIM_DIR:$PATH"
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.cache/terraform-plugins}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
export TF_IN_AUTOMATION=1 CHECKPOINT_DISABLE=1

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
selftest_fixture_env
build_reference "$id" "$OUT"
echo "reference of $id built (fixture config)"

# step <name> <dir> <cmd...>: run in dir; on failure print the output and exit 1.
step() {
  local name=$1 dir=$2 log rc=0
  shift 2
  log="$(mktemp -p "$OUT")"
  (cd "$dir" && "$@") >"$log" 2>&1 || rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "FAIL  $name"
    cat "$log"
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
  echo "ok    $name"
}

rel() { echo "${1#"$OUT"/}"; }

# ---- terraform -----------------------------------------------------------------------
tf_dirs=()
for root in "$OUT/live/terraform" "$OUT/modules"; do
  [[ -d "$root" ]] || continue
  while IFS= read -r d; do tf_dirs+=("$d"); done < <(
    find "$root" -name .terraform -prune -o -name '*.tf' -type f -printf '%h\n' | sort -u
  )
done

if [[ ${#tf_dirs[@]} -gt 0 ]]; then
  for tool in terraform tflint trivy; do
    command -v "$tool" >/dev/null || die 3 "$tool is required (scripts/install-dev-tools.sh)"
  done
  for root in "$OUT/live/terraform" "$OUT/modules"; do
    [[ -d "$root" ]] || continue
    step "fmt $(rel "$root")" "$root" terraform fmt -check -recursive -diff
  done
  step "tflint --init" "$REPO/tests" tflint --init --config "$REPO/tests/tflint.hcl"
  for d in "${tf_dirs[@]}"; do
    r="$(rel "$d")"
    step "init $r" "$d" terraform init -backend=false -input=false
    step "validate $r" "$d" terraform validate
    step "tflint $r" "$d" tflint --config "$REPO/tests/tflint.hcl"
    step "trivy $r" "$d" trivy config --quiet --severity HIGH,CRITICAL --exit-code 1 \
      --ignorefile "$REPO/tests/trivy-ignore.yaml" .
    if [[ -d "$d/tests" ]] && compgen -G "$d/tests/*.tftest.hcl" >/dev/null; then
      for tf in "$d"/tests/*.tftest.hcl; do
        if ! grep -q 'mock_provider' "$tf"; then
          echo "FAIL  test $r"
          echo "${tf#"$OUT"/} has no mock_provider; terraform test must never reach real providers"
          exit 1
        fi
      done
      # Credentials are bogus on purpose: nothing may reach real Azure.
      step "test $r" "$d" env ARM_USE_CLI=false ARM_USE_MSI=false ARM_USE_OIDC=false         ARM_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000         ARM_TENANT_ID=11111111-1111-1111-1111-111111111111         ARM_CLIENT_ID=00000000-0000-0000-0000-000000000000 ARM_CLIENT_SECRET=invalid         terraform test
    fi
  done
else
  echo "skip  terraform (no .tf files)"
fi

# is_playbook <file>: first meaningful line is a list item and a play-level hosts: key exists.
is_playbook() {
  awk '
    /^[[:space:]]*(#.*)?$/ || /^---[[:space:]]*$/ { next }
    !seen { seen = 1; if ($0 !~ /^- /) bad = 1 }
    /^(- |  )hosts:/ { h = 1 }
    END { exit !(seen && !bad && h) }
  ' "$1"
}

# ---- ansible -------------------------------------------------------------------------
AN="$OUT/live/ansible"
if [[ -d "$AN" ]]; then
  for tool in yamllint ansible-lint ansible-playbook; do
    command -v "$tool" >/dev/null || die 3 "$tool is required (scripts/install-dev-tools.sh)"
  done
  export ANSIBLE_LOCAL_TEMP="$OUT/.ansible-tmp" ANSIBLE_HOME="$OUT/.ansible-home"
  REQ="$AN/collections/requirements.yml"
  if [[ -f "$REQ" ]]; then
    command -v ansible-galaxy >/dev/null || die 3 "ansible-galaxy is required (scripts/install-dev-tools.sh)"
    COLL="$HOME/.cache/platform-practice/collections"
    mkdir -p "$COLL"
    step "galaxy collections" "$AN" ansible-galaxy collection install -r "$REQ" -p "$COLL"
    export ANSIBLE_COLLECTIONS_PATH="$COLL"
  fi
  step "yamllint ansible" "$AN" yamllint     -d '{extends: default, rules: {line-length: {max: 160}, truthy: {check-keys: false}}}' .
  step "ansible-lint ansible" "$AN" ansible-lint --profile production
  while IFS= read -r pb; do
    step "syntax-check ${pb#"$AN"/}" "$AN" ansible-playbook --syntax-check -i localhost, "$pb"
  done < <(
    find "$AN" \( -path '*/roles' -o -path '*/molecule' -o -path '*/collections' -o -path '*/group_vars' -o -path '*/host_vars' -o -path '*/inventor*' \) -prune -o       -type f \( -name '*.yml' -o -name '*.yaml' \) ! -name '*inventor*' -print | sort | while IFS= read -r f; do
      is_playbook "$f" && echo "$f"
    done
  )
  if [[ $molecule -eq 1 ]]; then
    command -v molecule >/dev/null || die 3 "molecule is required (scripts/install-dev-tools.sh)"
    while IFS= read -r m; do
      step "molecule $(rel "$(dirname "$m")")" "$(dirname "$m")" molecule test
    done < <(find "$AN" -type d -name molecule -path '*/roles/*' | sort)
  else
    echo "skip  molecule (--no-molecule)"
  fi
else
  echo "skip  ansible (no live/ansible)"
fi

echo "validate-reference $id: all steps ok"
