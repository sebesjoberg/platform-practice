# shellcheck shell=bash
# Config contract: $LAB_HOME/config.env

# The learner's own lab. A live selftest runs in a LAB_HOME of its own (init --selftest).
DEFAULT_LAB_HOME="$HOME/.platform-lab"

# lab_home_is_default: LAB_HOME is the learner's own lab (~/.platform-lab).
lab_home_is_default() {
  [[ "$(realpath -m "$LAB_HOME")" == "$(realpath -m "$DEFAULT_LAB_HOME")" ]]
}

# config_value <config.env> <key>: a value from a config file, read without sourcing it.
config_value() {
  sed -n "s/^$2=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$1" | tail -n1
}

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
    # the live selftest's own lab (init --selftest); never set in the learner's
    if [[ "${SELFTEST:-}" == 1 ]]; then printf 'SELFTEST="1"\n'; fi
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
  local prefix="" owner="" tag="" live_dir="" live_repo="" repo_mode="" refresh=0 selftest=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix) prefix=${2:?--prefix needs a value}; shift 2 ;;
      --gh-owner) owner=${2:?--gh-owner needs a value}; shift 2 ;;
      --owner-tag) tag=${2:?--owner-tag needs a value}; shift 2 ;;
      --live-dir) live_dir=${2:?--live-dir needs a value}; shift 2 ;;
      --live-repo) live_repo=${2:?--live-repo needs a value}; shift 2 ;;
      --create-repo) repo_mode=create; shift ;;
      --no-repo) repo_mode=skip; shift ;;
      --refresh-ip) refresh=1; shift ;;
      --selftest) selftest=1; shift ;;
      *) die 2 "init: unknown option $1" ;;
    esac
  done
  # --selftest: a lab only for ./lab.sh selftest, which resets repos and ends with nuke. Never in
  # the learner's own LAB_HOME.
  if [[ $selftest -eq 1 ]] && lab_home_is_default; then
    die 2 "init --selftest needs a LAB_HOME of its own, not $DEFAULT_LAB_HOME (e.g. LAB_HOME=~/.platform-lab-selftest ./lab.sh init --selftest --prefix lab ...)"
  fi

  if [[ $refresh -eq 1 ]]; then
    load_config
    LEARNER_IP="$(lookup_ip)" || die 1 "could not look up the learner IP"
    write_config
    echo "LEARNER_IP=$LEARNER_IP"
    # The SSH rule on nsg-<prefix>-hub-runner lives in the shared stack (tf-25), and CI reads
    # the address from the repo secret LEARNER_IP, not from config.env.
    echo "re-apply: shared (tf-25 NSG): rule allow-ssh-from-learner on nsg-$PREFIX-hub-runner"
    echo "  gh secret set LEARNER_IP -R $GH_OWNER/$LIVE_REPO --body $LEARNER_IP"
    echo "  gh workflow run terraform.yml -R $GH_OWNER/$LIVE_REPO --ref main -f stacks=shared"
    return 0
  fi

  # Re-init: SUFFIX survives; inputs fall back to old values; derived values are recomputed.
  local old_prefix=""
  if [[ -f "$LAB_HOME/config.env" ]]; then
    # shellcheck disable=SC1091
    source "$LAB_HOME/config.env"
    old_prefix=${PREFIX:-}
  fi
  # shellcheck disable=SC2034 # read in write_config
  [[ $selftest -eq 1 ]] && SELFTEST=1
  local old_live_dir=${LIVE_DIR:-} old_live_repo=${LIVE_REPO:-}
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

  # The platform repo: asked (default <prefix>-platform); a re-init with the same prefix keeps it.
  LIVE_REPO=$live_repo
  [[ -z "$LIVE_REPO" && -n "$old_live_repo" && "$old_prefix" == "$PREFIX" ]] && LIVE_REPO=$old_live_repo
  ask LIVE_REPO --live-repo "Platform repo on GitHub (created if missing)" "${PREFIX}-platform"
  [[ "$LIVE_REPO" =~ ^[A-Za-z0-9._-]+$ ]] || die 2 "init: --live-repo must be a repo name (A-Za-z0-9 . _ -)"
  MODULES_REPO="${PREFIX}-terraform-modules"
  if [[ -n "$live_dir" ]]; then
    LIVE_DIR=$live_dir
  elif [[ -n "$old_live_dir" && "$old_prefix" == "$PREFIX" && "$old_live_repo" == "$LIVE_REPO" ]]; then
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

  # The platform repo: ask on a terminal, --create-repo / --no-repo otherwise. A selftest lab's
  # repos come from catchup tf-01.
  if [[ -z "$repo_mode" ]]; then
    if [[ $selftest -eq 1 || "${SELFTEST:-}" == 1 ]]; then repo_mode=skip
    elif [[ -t 0 ]]; then repo_mode=ask
    else repo_mode=hint
    fi
  fi
  init_live_repo "$repo_mode"
}

# init_live_repo <ask|create|hint|skip>: make sure GH_OWNER/LIVE_REPO exists on GitHub (public)
# and is cloned to LIVE_DIR. Never fails init: anything left undone is printed as a next step.
init_live_repo() {
  local mode=$1 repo="$GH_OWNER/$LIVE_REPO" vis reply
  case "$mode" in
    skip) return 0 ;;
    hint)
      echo "repo: not checked (no terminal). ./lab.sh init --create-repo creates and clones $repo"
      return 0
      ;;
  esac
  need gh git
  if vis="$(gh repo view "$repo" --json visibility --jq .visibility 2>/dev/null)"; then
    echo "repo: found https://github.com/$repo"
    if [[ "$vis" != PUBLIC ]]; then
      echo "repo: $repo is ${vis,,}; the lab needs it public: gh repo edit $repo --visibility public --accept-visibility-change-consequences"
    fi
  else
    if [[ "$mode" == ask ]]; then
      read -r -p "Create the public repo $repo on GitHub and clone it to $LIVE_DIR? [Y/n] " reply
      if [[ "$reply" =~ ^[Nn] ]]; then
        echo "repo: not created. Create it yourself (tf-01), or run ./lab.sh init --create-repo"
        return 0
      fi
    fi
    gh repo create "$repo" --public --description "Acme platform (platform-practice lab)" >/dev/null ||
      die 1 "init: gh repo create $repo failed (is gh logged in? gh auth status)"
    echo "repo: created https://github.com/$repo"
  fi

  if [[ -d "$LIVE_DIR/.git" ]]; then
    echo "repo: $LIVE_DIR is already a clone"
    return 0
  fi
  if [[ -e "$LIVE_DIR" && -n "$(ls -A "$LIVE_DIR" 2>/dev/null)" ]]; then
    echo "repo: $LIVE_DIR exists and is not empty; clone $repo there yourself: gh repo clone $repo <dir>"
    return 0
  fi
  mkdir -p "$(dirname "$LIVE_DIR")"
  gh repo clone "$repo" "$LIVE_DIR" -- -q 2>/dev/null ||
    die 1 "init: gh repo clone $repo $LIVE_DIR failed"
  # An empty clone may start on master (init.defaultBranch); the lab works on main.
  if [[ -d "$LIVE_DIR/.git" ]] && ! git -C "$LIVE_DIR" rev-parse -q --verify HEAD >/dev/null; then
    git -C "$LIVE_DIR" symbolic-ref HEAD refs/heads/main
  fi
  echo "repo: cloned to $LIVE_DIR"
}
