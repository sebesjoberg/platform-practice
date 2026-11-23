# shellcheck shell=bash
# The lab's app image in the shared registry (tf-22). Terraform never pushes images: the learner
# imports Microsoft's Container Apps quickstart image once with az acr import. A registry that
# pause destroyed comes back empty, so tf-22's catchup, tf-05's catchup (before the pipeline
# needs the image) and ./lab.sh resume (lib/ops.sh) import it again through these helpers.
# Needs the config (PREFIX, SUFFIX) and az.

ACR_HELLO_SOURCE="mcr.microsoft.com/k8se/quickstart:latest"
ACR_HELLO_IMAGE="hello:1.0"

acr_name() { echo "acr$PREFIX$SUFFIX"; }

# acr_hello_needed <live dir>: the live tree runs the image (a container app, tf-23 on).
acr_hello_needed() {
  grep -rqsE '/hello:1\.0"' "$1/terraform" --include='*.tf'
}

# acr_ready: the registry exists and is provisioned.
acr_ready() {
  [[ "$(az acr show -n "$(acr_name)" --query provisioningState -o tsv 2>/dev/null | tr -d '\r')" == Succeeded ]]
}

# acr_hello_present: hello:1.0 is in the registry.
acr_hello_present() {
  az acr repository show -n "$(acr_name)" --image "$ACR_HELLO_IMAGE" -o none 2>/dev/null
}

# acr_hello_import: import hello:1.0 unless it is already there.
acr_hello_import() {
  if acr_hello_present; then
    echo "$(acr_name): $ACR_HELLO_IMAGE is already there"
    return 0
  fi
  az acr import --name "$(acr_name)" --source "$ACR_HELLO_SOURCE" --image "$ACR_HELLO_IMAGE" -o none &&
    echo "$(acr_name): imported $ACR_HELLO_SOURCE as $ACR_HELLO_IMAGE"
}

# acr_wait_ready <seconds>: wait until the registry is provisioned (a pipeline run creates it).
acr_wait_ready() {
  local deadline=$((SECONDS + $1))
  until acr_ready; do
    if ((SECONDS >= deadline)); then
      echo "$(acr_name) did not appear within $1 s" >&2
      return 1
    fi
    sleep "${ACR_POLL_SECONDS:-20}"
  done
}
