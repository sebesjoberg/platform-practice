# shellcheck shell=bash
# Shared helpers. Sourced by lab.sh.

# Tests point this at a scratch dir; on a real system Windows binaries live under /mnt/.
WINDOWS_MOUNT_PREFIX="${WINDOWS_MOUNT_PREFIX:-/mnt/}"

die() {
  local code=$1
  shift
  echo "$*" >&2
  exit "$code"
}

require_linux_env() {
  if [[ "$(uname -s)" != "Linux" || -n "${MSYSTEM:-}" ]]; then
    die 3 "run the lab inside WSL/Linux"
  fi
}

# need <tool...>: exit 3 when a tool is missing or is the Windows build.
need() {
  local tool path hint
  for tool in "$@"; do
    case "$tool" in
      az) hint="https://learn.microsoft.com/cli/azure/install-azure-cli-linux" ;;
      gh) hint="https://github.com/cli/cli/blob/trunk/docs/install_linux.md" ;;
      terraform) hint="https://developer.hashicorp.com/terraform/install" ;;
      jq) hint="apt install jq (or download from https://jqlang.org)" ;;
      *) hint="install it with your package manager" ;;
    esac
    path="$(type -P "$tool" || true)"
    [[ -n "$path" ]] || die 3 "$tool is missing; install the Linux one: $hint"
    [[ "$path" != "$WINDOWS_MOUNT_PREFIX"* ]] ||
      die 3 "$tool is the Windows build; install the Linux one: $hint"
  done
}
