# shellcheck shell=bash
# Spoke module helpers for the checks of tf-15…tf-20 (sourced by checks.sh; cwd = LIVE_DIR).
# The module lives in the live repo at terraform/modules/spoke from tf-15, and in the modules
# repo at $MODULES_DIR/spoke from tf-19. Checks look wherever it is, so `./lab.sh grade --all`
# still passes after the move.

# spoke_module_dir: prints the module's directory ($MODULES_DIR/spoke first), 1 if neither has
# .tf files.
spoke_module_dir() {
  local d
  for d in "${MODULES_DIR:+$MODULES_DIR/spoke}" terraform/modules/spoke; do
    [[ -n "$d" ]] || continue
    if compgen -G "$d/*.tf" >/dev/null; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

# tf_blocks_missing <dir> <kind> <attr>: names of the top-level <kind> blocks (variable, output)
# in <dir>/*.tf that have no <attr> = ... line. Assumes terraform fmt layout.
tf_blocks_missing() {
  local dir=$1 kind=$2 attr=$3
  awk -v kind="$kind" -v attr="$attr" '
    !inb && $1 == kind && $2 ~ /^"/ {
      name = $2; gsub(/"/, "", name); inb = 1; has = 0
      if ($0 ~ /\}[[:space:]]*$/) { print name; inb = 0 }
      next
    }
    inb && $0 ~ ("^[[:space:]]+" attr "[[:space:]]*=") { has = 1 }
    inb && /^\}/ { if (!has) print name; inb = 0 }
  ' "$dir"/*.tf
}

# tf_block <dir> <kind> <name>: prints the top-level block `<kind> "<name>" {` … `}` from
# <dir>/*.tf (nothing if there is none).
tf_block() {
  local dir=$1 kind=$2 name=$3
  awk -v kind="$kind" -v want="\"$name\"" '
    !inb && $1 == kind && $2 == want { inb = 1 }
    inb { print }
    inb && /^\}/ { inb = 0 }
  ' "$dir"/*.tf
}
