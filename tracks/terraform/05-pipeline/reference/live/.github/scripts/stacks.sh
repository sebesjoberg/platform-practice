#!/usr/bin/env bash
# Print the Terraform stacks to run, space separated, in dependency order.
#   .github/scripts/stacks.sh [all | "stack stack" | "stack,stack"]
# A stack is a directory under terraform/ with an azurerm backend. bootstrap is excluded: it is
# applied locally only, CI must never manage its own identity. STACK_ORDER (env, optional) lists
# the dependency order; stacks found but not listed follow alphabetically.
set -euo pipefail
set -f

requested="${1:-all}"
order="${STACK_ORDER:-landing-zone shared env-dev env-prod observability teams/payments}"

found=""
if [[ -d terraform ]]; then
  found=$(grep -rlE --include='*.tf' 'backend[[:space:]]+"azurerm"' terraform |
    xargs -r -n1 dirname | sed 's|^terraform/||' | grep -vx bootstrap | sort -u || true)
fi

ordered=""
for s in $order; do
  if grep -qx -- "$s" <<<"$found"; then ordered="$ordered $s"; fi
done
for s in $found; do
  if [[ " $ordered " != *" $s "* ]]; then ordered="$ordered $s"; fi
done

if [[ "$requested" != all ]]; then
  want=" ${requested//,/ } "
  for w in $want; do
    if [[ " $ordered " != *" $w "* ]]; then
      echo "::error::unknown stack: $w" >&2
      exit 1
    fi
  done
  selected=""
  for s in $ordered; do
    if [[ "$want" == *" $s "* ]]; then selected="$selected $s"; fi
  done
  ordered=$selected
fi

echo "${ordered# }"
