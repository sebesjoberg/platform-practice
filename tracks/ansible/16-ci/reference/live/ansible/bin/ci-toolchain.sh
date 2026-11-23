#!/usr/bin/env bash
# The Ansible toolchain for CI on the self-hosted runner (an-16), built once per set of pins and
# kept in the runner user's home: a self-hosted runner keeps its files between jobs, and the Azure
# SDK takes minutes to install on the 1 GiB jump host. Only what applying needs: ansible-core, the
# collections and the Azure collection's Python packages (linters and Molecule run on
# GitHub-hosted runners).
#   bash ansible/bin/ci-toolchain.sh
# In a workflow step it puts the venv on GITHUB_PATH and the collections on
# ANSIBLE_COLLECTIONS_PATH (GITHUB_ENV) for the following steps.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

key="$(cat requirements.txt collections/requirements.yml | sha256sum | cut -c1-16)"
cache="${ACME_TOOLCHAIN_CACHE:-$HOME/.cache/acme-ansible}"
venv="$cache/$key"

# A venv can't be moved after it is built: build it in place, mark it complete at the end, and
# start over when the mark is missing (an interrupted build).
if [[ ! -f "$venv/.complete" ]]; then
  echo "ci-toolchain: building $venv"
  rm -rf "$venv"
  mkdir -p "$cache"
  python3 -m venv "$venv"
  "$venv/bin/pip" install -q --upgrade pip
  "$venv/bin/pip" install -q "$(grep -E '^ansible-core==' requirements.txt)"
  "$venv/bin/ansible-galaxy" collection install -r collections/requirements.yml -p "$venv/collections"
  "$venv/bin/pip" install -q -r "$venv/collections/ansible_collections/azure/azcollection/requirements.txt"
  touch "$venv/.complete"
fi
# Older toolchains (other pins) go.
find "$cache" -mindepth 1 -maxdepth 1 ! -name "$key" -exec rm -rf {} +

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$venv/bin" >>"$GITHUB_PATH"
  echo "ANSIBLE_COLLECTIONS_PATH=$venv/collections" >>"$GITHUB_ENV"
fi
echo "ci-toolchain: $venv ($("$venv/bin/ansible" --version | head -n1))"
