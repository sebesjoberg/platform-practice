#!/usr/bin/env bash
# platform-practice: Terraform + Ansible on Azure practice lab.
#
#   ./lab.sh init [--prefix P --gh-owner O --owner-tag T --live-dir D --selftest | --refresh-ip]
#   ./lab.sh next [track]       start the next task
#   ./lab.sh task|hint|solution [id]
#   ./lab.sh status
#   ./lab.sh grade|catchup|pause|resume|nuke|cost
#   ./lab.sh selftest [--offline] [track] [--from id] [--to id]
set -euo pipefail

# Exported: task scripts (e.g. tracks/terraform/lib/modules-tag.sh) source lib/ from here.
LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LAB_ROOT
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
# shellcheck source=lib/template.sh
source "$LAB_ROOT/lib/template.sh"
# shellcheck source=lib/catchup.sh
source "$LAB_ROOT/lib/catchup.sh"
# shellcheck source=lib/ops.sh
source "$LAB_ROOT/lib/ops.sh"
# shellcheck source=lib/selftest.sh
source "$LAB_ROOT/lib/selftest.sh"
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
  catchup) cmd_catchup "$@" ;;
  pause) cmd_pause ;;
  resume) cmd_resume ;;
  nuke) cmd_nuke ;;
  cost) cmd_cost ;;
  selftest) cmd_selftest "$@" ;;
  *)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
