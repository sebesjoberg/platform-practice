#!/usr/bin/env bash
# tf-27 setup (./lab.sh next): the incident, made with az as a teammate in the portal would:
#   - the owner tag of rg-<prefix>-dev changes to "ops-oncall". (Removing it isn't possible: the
#     owner-tag policy of tf-11 denies any update that leaves an rg-* group without one.)
#   - an inbound rule AllowAll-Temp (any protocol, source and port) on nsg-<prefix>-dev-app
# The first run records the time in $LAB_HOME/snapshots/tf-27.start (the grader wants a green
# drift.yml run after it) and injects; later runs never inject again, so they can't undo the
# learner's reconcile. Prints only what the teammate would say. Idempotent.
set -euo pipefail

: "${LAB_HOME:=$HOME/.platform-lab}"
: "${PREFIX:?PREFIX not set; run ./lab.sh init}"
rg="rg-$PREFIX-dev"
marker="$LAB_HOME/snapshots/tf-27.start"

if [[ ! -s "$marker" ]]; then
  az group update -n "$rg" --set tags.owner=ops-oncall -o none
  az network nsg rule create -g "$rg" --nsg-name "nsg-$PREFIX-dev-app" -n AllowAll-Temp \
    --priority 100 --direction Inbound --access Allow --protocol '*' \
    --source-address-prefixes '*' --source-port-ranges '*' \
    --destination-address-prefixes '*' --destination-port-ranges '*' \
    --description "temp, debugging" -o none
  mkdir -p "$(dirname "$marker")"
  date +%s >"$marker"
fi

cat <<EOF
Message from Kim (security):

  "Morning! Our scanner says the dev web subnet has been open to the whole internet since last
   night, and the cost report suddenly lists $rg under somebody called ops-oncall. Nobody
   merged anything to the platform repo. Can you find out what changed, put it right, and make
   sure we hear about this kind of thing before the auditors do?"
EOF
