#!/usr/bin/env bash
# platform-practice: Terraform + Ansible on Azure practice lab.
#
#   ./lab.sh init [--prefix P --gh-owner O --owner-tag T --live-dir D | --refresh-ip]
#   ./lab.sh next [track]       start the next task
#   ./lab.sh task|hint|solution [id]
#   ./lab.sh status
#   ./lab.sh grade|catchup|pause|resume|nuke|cost|selftest   (later tasks)
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LAB_HOME="${LAB_HOME:-$HOME/.platform-lab}"
export TRACKS_DIR="${TRACKS_DIR:-$LAB_ROOT/tracks}"

# shellcheck source=lib/common.sh
source "$LAB_ROOT/lib/common.sh"
# shellcheck source=lib/config.sh
source "$LAB_ROOT/lib/config.sh"
# shellcheck source=lib/tasks.sh
source "$LAB_ROOT/lib/tasks.sh"
# shellcheck source=lib/grade.sh
source "$LAB_ROOT/lib/grade.sh"
# shellcheck source=lib/progress.sh
source "$LAB_ROOT/lib/progress.sh"

require_linux_env

cmd="${1:-}"
[[ $# -gt 0 ]] && shift
case "$cmd" in
  init) cmd_init "$@" ;;
  next)
    load_config
    cmd_next "$@"
    ;;
  task) cmd_show task.md "$@" ;;
  hint) cmd_show hint.md "$@" ;;
  solution) cmd_show solution.md "$@" ;;
  status) cmd_status ;;
  grade) cmd_grade "$@" ;;
  catchup | pause | resume | nuke | cost | selftest)
    echo "not implemented yet" >&2
    exit 2
    ;;
  *)
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
