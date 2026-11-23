# shellcheck shell=bash
# Config contract: $LAB_HOME/config.env

load_config() {
  [[ -f "$LAB_HOME/config.env" ]] || die 1 "no config; run ./lab.sh init first"
  set -a
  # shellcheck disable=SC1091
  source "$LAB_HOME/config.env"
  set +a
}

# write_config: writes config.env from the current shell variables.
write_config() {
  mkdir -p "$LAB_HOME"
  local key keys="PREFIX SUFFIX LOCATION SUBSCRIPTION_ID TENANT_ID GH_OWNER LIVE_REPO MODULES_REPO LIVE_DIR MODULES_DIR LEARNER_IP OWNER_TAG"
  # config.env is sourced: refuse anything that could break quoting or run code.
  for key in $keys; do
    [[ "${!key}" =~ ^[A-Za-z0-9._/~@:+\ -]*$ ]] ||
      die 2 "init: unsafe value for $key (allowed: A-Za-z0-9 . _ / ~ @ : + space -)"
  done
  {
    for key in $keys; do
      printf '%s="%s"\n' "$key" "${!key}"
    done
  } >"$LAB_HOME/config.env.tmp"
  mv "$LAB_HOME/config.env.tmp" "$LAB_HOME/config.env"
}

lookup_ip() {
  curl -fsS https://api.ipify.org | tr -d '[:space:]'
}

random_suffix() {
  LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6 || true
}

# ask <var> <flag> <prompt> <default>: keep the value if set, else prompt (TTY), else default or fail.
ask() {
  local var=$1 flag=$2 prompt=$3 def=$4 reply
  if [[ -n "${!var:-}" ]]; then return 0; fi
  if [[ -t 0 ]]; then
    read -r -p "$prompt${def:+ [$def]}: " reply
    printf -v "$var" '%s' "${reply:-$def}"
  elif [[ -n "$def" ]]; then
    printf -v "$var" '%s' "$def"
  else
    die 2 "init: missing $flag"
  fi
}

cmd_init() {
  need az curl jq
  local prefix="" owner="" tag="" live_dir="" refresh=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix) prefix=${2:?--prefix needs a value}; shift 2 ;;
      --gh-owner) owner=${2:?--gh-owner needs a value}; shift 2 ;;
      --owner-tag) tag=${2:?--owner-tag needs a value}; shift 2 ;;
      --live-dir) live_dir=${2:?--live-dir needs a value}; shift 2 ;;
      --refresh-ip) refresh=1; shift ;;
      *) die 2 "init: unknown option $1" ;;
    esac
  done

  if [[ $refresh -eq 1 ]]; then
    load_config
    LEARNER_IP="$(lookup_ip)" || die 1 "could not look up the learner IP"
    write_config
    echo "LEARNER_IP=$LEARNER_IP"
    echo "re-apply: shared (tf-25 NSG)"
    return 0
  fi

  # Re-init: SUFFIX survives; inputs fall back to old values; derived values are recomputed.
  local old_prefix=""
  if [[ -f "$LAB_HOME/config.env" ]]; then
    # shellcheck disable=SC1091
    source "$LAB_HOME/config.env"
    old_prefix=${PREFIX:-}
  fi
  local old_live_dir=${LIVE_DIR:-}
  unset LIVE_REPO MODULES_REPO MODULES_DIR LIVE_DIR

  PREFIX="${prefix:-${PREFIX:-}}"
  ask PREFIX --prefix "Resource prefix (2-6 lowercase letters)" acme
  [[ "$PREFIX" =~ ^[a-z]{2,6}$ ]] || die 2 "init: --prefix must match ^[a-z]{2,6}$"

  GH_OWNER="${owner:-${GH_OWNER:-}}"
  if [[ -z "$GH_OWNER" ]]; then
    need gh
    GH_OWNER="$(gh api user --jq .login 2>/dev/null || true)"
  fi
  ask GH_OWNER --gh-owner "GitHub owner" ""

  OWNER_TAG="${tag:-${OWNER_TAG:-}}"
  ask OWNER_TAG --owner-tag "Owner tag (your name/alias)" ""

  LIVE_REPO="${PREFIX}-platform"
  MODULES_REPO="${PREFIX}-terraform-modules"
  if [[ -n "$live_dir" ]]; then
    LIVE_DIR=$live_dir
  elif [[ -n "$old_live_dir" && "$old_prefix" == "$PREFIX" ]]; then
    LIVE_DIR=$old_live_dir
  else
    LIVE_DIR="$HOME/acme/$LIVE_REPO"
  fi
  # shellcheck disable=SC2034 # read in write_config
  MODULES_DIR="$(dirname "$LIVE_DIR")/$MODULES_REPO"
  # shellcheck disable=SC2034 # read via indirect expansion in write_config
  LOCATION=swedencentral
  SUFFIX="${SUFFIX:-$(random_suffix)}"

  local acct me owners
  acct="$(az account show --query '{id:id,tenantId:tenantId}' -o json)" ||
    die 3 "az account show failed; run az login first"
  SUBSCRIPTION_ID="$(jq -r .id <<<"$acct" | tr -d '\r')"
  # shellcheck disable=SC2034
  TENANT_ID="$(jq -r .tenantId <<<"$acct" | tr -d '\r')"

  me="$(az ad signed-in-user show --query id -o tsv | tr -d '\r')" ||
    die 3 "could not read the signed-in user"
  owners="$(az role assignment list --assignee "$me" --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --query "[?roleDefinitionName=='Owner']" -o json)" || die 3 "could not list role assignments"
  [[ "$(jq 'length' <<<"$owners" | tr -d '\r')" -gt 0 ]] ||
    die 3 "you need the Owner role on subscription $SUBSCRIPTION_ID (role assignments and policy need it)"

  LEARNER_IP="$(lookup_ip)" || die 1 "could not look up the learner IP"
  write_config
  echo "wrote $LAB_HOME/config.env"
}
