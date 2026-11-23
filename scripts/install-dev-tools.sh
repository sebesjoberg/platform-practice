#!/usr/bin/env bash
# Installs the offline dev toolchain in user space (no sudo):
#   binaries -> ~/.local/bin      (terraform, tflint, trivy, terraform-docs, shellcheck, bats)
#   python   -> ~/.local/share/platform-practice/venv
#               (ansible-core, ansible-lint, yamllint, molecule, molecule-plugins[docker])
# Idempotent: a tool whose installed version already matches is skipped.
set -euo pipefail

# ---- pinned versions (latest stable at 2026-11-23) --------------------------
TERRAFORM_VERSION=1.17.2
TFLINT_VERSION=0.66.0
TRIVY_VERSION=0.76.2
TERRAFORM_DOCS_VERSION=0.25.1
SHELLCHECK_VERSION=0.11.0
BATS_VERSION=1.14.0

# 2.22.x needs Python >=3.13; Ubuntu 24.04 ships 3.12, so pin the newest 2.21 release.
ANSIBLE_CORE_VERSION=2.21.6
ANSIBLE_LINT_VERSION=26.11.0
YAMLLINT_VERSION=1.38.0
MOLECULE_VERSION=26.11.0
MOLECULE_PLUGINS_VERSION=26.11.0

# Shellcheck and bats-core publish no checksum file upstream, so their SHA256
# is pinned here (computed from the release assets when the pin was made).
SHELLCHECK_SHA256=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
BATS_SHA256=bb537b70b15b732f6d8827dd6578e3d8ce166636ce1f18ea9a074184fcce9177
# -----------------------------------------------------------------------------

BIN_DIR="${HOME}/.local/bin"
SHARE_DIR="${HOME}/.local/share/platform-practice"
VENV_DIR="${SHARE_DIR}/venv"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$BIN_DIR" "$SHARE_DIR"

log() { printf '==> %s\n' "$*"; }

# download <url> <dest>
download() { curl -fsSL --retry 3 -o "$2" "$1"; }

# verify_sha256 <file> <expected>
verify_sha256() {
  local actual
  actual=$(sha256sum "$1" | cut -d' ' -f1)
  if [[ "$actual" != "$2" ]]; then
    echo "checksum mismatch for $(basename "$1"): expected $2, got $actual" >&2
    exit 1
  fi
}

# verify_from_sums <file> <sums-file>: the sums file lists "<sha>  <basename>"
verify_from_sums() {
  local expected
  expected=$(awk -v f="$(basename "$1")" '$2 == f || $2 == "*" f {print $1}' "$2")
  [[ -n "$expected" ]] || { echo "no checksum for $(basename "$1") in $(basename "$2")" >&2; exit 1; }
  verify_sha256 "$1" "$expected"
}

# unzip_to <zip> <dir>: no unzip binary needed
unzip_to() { python3 -m zipfile -e "$1" "$2"; }

install_terraform() {
  local v=$TERRAFORM_VERSION cur
  cur=$("$BIN_DIR/terraform" version 2>/dev/null | sed -n '1s/^Terraform v//p' || true)
  if [[ "$cur" == "$v" ]]; then log "terraform $v already installed"; return; fi
  log "installing terraform $v"
  local base="https://releases.hashicorp.com/terraform/$v" z="terraform_${v}_linux_amd64.zip"
  download "$base/$z" "$WORK_DIR/$z"
  download "$base/terraform_${v}_SHA256SUMS" "$WORK_DIR/terraform.sums"
  verify_from_sums "$WORK_DIR/$z" "$WORK_DIR/terraform.sums"
  unzip_to "$WORK_DIR/$z" "$WORK_DIR/terraform-x"
  install -m 0755 "$WORK_DIR/terraform-x/terraform" "$BIN_DIR/terraform"
}

install_tflint() {
  local v=$TFLINT_VERSION cur
  cur=$("$BIN_DIR/tflint" --version 2>/dev/null | sed -n '1s/^TFLint version //p' || true)
  if [[ "$cur" == "$v" ]]; then log "tflint $v already installed"; return; fi
  log "installing tflint $v"
  local base="https://github.com/terraform-linters/tflint/releases/download/v$v" z=tflint_linux_amd64.zip
  download "$base/$z" "$WORK_DIR/$z"
  download "$base/checksums.txt" "$WORK_DIR/tflint.sums"
  verify_from_sums "$WORK_DIR/$z" "$WORK_DIR/tflint.sums"
  unzip_to "$WORK_DIR/$z" "$WORK_DIR/tflint-x"
  install -m 0755 "$WORK_DIR/tflint-x/tflint" "$BIN_DIR/tflint"
}

install_trivy() {
  local v=$TRIVY_VERSION cur
  cur=$("$BIN_DIR/trivy" --version 2>/dev/null | sed -n '1s/^Version: //p' || true)
  if [[ "$cur" == "$v" ]]; then log "trivy $v already installed"; return; fi
  log "installing trivy $v"
  local base="https://github.com/aquasecurity/trivy/releases/download/v$v" z="trivy_${v}_Linux-64bit.tar.gz"
  download "$base/$z" "$WORK_DIR/$z"
  download "$base/trivy_${v}_checksums.txt" "$WORK_DIR/trivy.sums"
  verify_from_sums "$WORK_DIR/$z" "$WORK_DIR/trivy.sums"
  mkdir -p "$WORK_DIR/trivy-x"
  tar -xzf "$WORK_DIR/$z" -C "$WORK_DIR/trivy-x" trivy
  install -m 0755 "$WORK_DIR/trivy-x/trivy" "$BIN_DIR/trivy"
}

install_terraform_docs() {
  local v=$TERRAFORM_DOCS_VERSION cur
  cur=$("$BIN_DIR/terraform-docs" --version 2>/dev/null | sed -n '1s/^terraform-docs version v\([0-9.]*\).*/\1/p' || true)
  if [[ "$cur" == "$v" ]]; then log "terraform-docs $v already installed"; return; fi
  log "installing terraform-docs $v"
  local base="https://github.com/terraform-docs/terraform-docs/releases/download/v$v" z="terraform-docs-v${v}-linux-amd64.tar.gz"
  download "$base/$z" "$WORK_DIR/$z"
  download "$base/terraform-docs-v${v}.sha256sum" "$WORK_DIR/tfdocs.sums"
  verify_from_sums "$WORK_DIR/$z" "$WORK_DIR/tfdocs.sums"
  mkdir -p "$WORK_DIR/tfdocs-x"
  tar -xzf "$WORK_DIR/$z" -C "$WORK_DIR/tfdocs-x" terraform-docs
  install -m 0755 "$WORK_DIR/tfdocs-x/terraform-docs" "$BIN_DIR/terraform-docs"
}

install_shellcheck() {
  local v=$SHELLCHECK_VERSION cur
  cur=$("$BIN_DIR/shellcheck" --version 2>/dev/null | sed -n 's/^version: //p' || true)
  if [[ "$cur" == "$v" ]]; then log "shellcheck $v already installed"; return; fi
  log "installing shellcheck $v"
  local z="shellcheck-v${v}.linux.x86_64.tar.xz"
  download "https://github.com/koalaman/shellcheck/releases/download/v$v/$z" "$WORK_DIR/$z"
  verify_sha256 "$WORK_DIR/$z" "$SHELLCHECK_SHA256"
  mkdir -p "$WORK_DIR/sc-x"
  tar -xJf "$WORK_DIR/$z" -C "$WORK_DIR/sc-x" --strip-components=1 "shellcheck-v${v}/shellcheck"
  install -m 0755 "$WORK_DIR/sc-x/shellcheck" "$BIN_DIR/shellcheck"
}

install_bats() {
  local v=$BATS_VERSION cur
  cur=$("$BIN_DIR/bats" --version 2>/dev/null | sed -n '1s/^Bats //p' || true)
  if [[ "$cur" == "$v" ]]; then log "bats-core $v already installed"; return; fi
  log "installing bats-core $v"
  local z="bats-core-${v}.tar.gz"
  download "https://github.com/bats-core/bats-core/archive/refs/tags/v$v.tar.gz" "$WORK_DIR/$z"
  verify_sha256 "$WORK_DIR/$z" "$BATS_SHA256"
  mkdir -p "$WORK_DIR/bats-x"
  tar -xzf "$WORK_DIR/$z" -C "$WORK_DIR/bats-x" --strip-components=1
  "$WORK_DIR/bats-x/install.sh" "${HOME}/.local" >/dev/null
}

# pip_version <package>: installed version in the venv, empty if absent
pip_version() {
  "$VENV_DIR/bin/python" -m pip show "$1" 2>/dev/null | sed -n 's/^Version: //p' || true
}

install_python_tools() {
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    log "creating venv $VENV_DIR"
    python3 -m venv "$VENV_DIR"
  fi
  local todo=() spec name ver
  for spec in \
    "ansible-core==$ANSIBLE_CORE_VERSION" \
    "ansible-lint==$ANSIBLE_LINT_VERSION" \
    "yamllint==$YAMLLINT_VERSION" \
    "molecule==$MOLECULE_VERSION" \
    "molecule-plugins==$MOLECULE_PLUGINS_VERSION"; do
    name=${spec%%==*}
    ver=${spec##*==}
    if [[ "$(pip_version "$name")" == "$ver" ]]; then
      log "$name $ver already installed"
    else
      todo+=("$spec")
    fi
  done
  # The [docker] extra pulls in the docker SDK; reinstall with the extra if it is missing.
  if [[ -z "$(pip_version docker)" ]]; then
    todo+=("molecule-plugins[docker]==$MOLECULE_PLUGINS_VERSION")
  fi
  if ((${#todo[@]} == 0)); then return; fi
  log "pip install: ${todo[*]}"
  "$VENV_DIR/bin/python" -m pip install --quiet --disable-pip-version-check "${todo[@]}"
}

install_terraform
install_tflint
install_trivy
install_terraform_docs
install_shellcheck
install_bats
install_python_tools

log "done. PATH: export PATH=\"\$HOME/.local/bin:\$PATH\"   venv: source $VENV_DIR/bin/activate"
