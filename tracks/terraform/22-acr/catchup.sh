#!/usr/bin/env bash
# tf-22 catchup (after-push, cwd = LIVE_DIR): import the app image into the shared registry, as
# the learner does with az acr import. tf-05's hook has run the pipeline, which created the
# registry (and, from tf-23 on, already imported the image before the container app needed it).
# Idempotent.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/acr-image.sh"
acr_wait_ready 600
acr_hello_import
