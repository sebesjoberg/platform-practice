# tf-25 checks (sourced by the grader; cwd = LIVE_DIR; MODULES_DIR = the modules repo clone)

# Pipeline runs that applied something (tf-24 skips apply when no Terraform path changed).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ci-runs.sh"
export -f ci_main_green ci_run_apply

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/app-env.sh"
export TF25_LIVE="$GH_OWNER/$LIVE_REPO" TF25_MODS="$GH_OWNER/$MODULES_REPO"
export TF25_SRC="source[[:space:]]*=[[:space:]]*\"git::https://github\\.com/$GH_OWNER/$MODULES_REPO\\.git//linux-vm\\?ref=v[0-9]+\\.[0-9]+\\.[0-9]+\""
export TF25_KEY="$HOME/.ssh/${PREFIX}_lab" TF25_USER=azureuser
export TF25_SIZE=Standard_B2ats_v2
export TF25_VM_JQ='.hardwareProfile.vmSize == env.TF25_SIZE and .storageProfile.imageReference.publisher == "Canonical"
  and .storageProfile.imageReference.offer == "ubuntu-24_04-lts" and .osProfile.linuxConfiguration.disablePasswordAuthentication == true
  and (.osProfile.linuxConfiguration.ssh.publicKeys | length) > 0 and .location == env.LOCATION'
# Inbound allow rules that open TCP 22 (single port, *, a range or a list), all from LEARNER_IP.
export TF25_NSG_JQ='def covers22: ([.destinationPortRange // empty] + (.destinationPortRanges // []))
    | any(. == "22" or . == "*" or (test("^[0-9]+-[0-9]+$") and (split("-") | (.[0] | tonumber) <= 22 and (.[1] | tonumber) >= 22)));
  def mine: ((.sourceAddressPrefixes // []) | length) == 0 and (.sourceAddressPrefix == env.LEARNER_IP + "/32" or .sourceAddressPrefix == env.LEARNER_IP);
  [.[] | select(.direction == "Inbound" and .access == "Allow" and (.protocol == "Tcp" or .protocol == "*") and covers22)] as $r
  | ($r | length) > 0 and all($r[]; mine)'

# tf25_vm <rg> <name> <role> <env> <vnet> <subnet> <public: yes|no>: the VM matches the lab's
# image, size and SSH settings, carries the role/env tags, and its NIC sits in <vnet>/<subnet>
# with or without a public IP.
tf25_vm() {
  local vm nic
  vm="$(az vm show -g "$1" -n "$2" -o json)" || return 1
  jq -e --arg r "$3" --arg e "$4" "$TF25_VM_JQ and .tags.role == \$r and .tags.env == \$e" <<<"$vm" >/dev/null || return 1
  nic="$(az network nic show --ids "$(jq -r '.networkProfile.networkInterfaces[0].id' <<<"$vm")" -o json)" || return 1
  jq -e --arg v "$5" --arg s "$6" --arg p "$7" '.ipConfigurations[0] as $c
    | ($c.subnet.id | ascii_downcase | endswith("/virtualnetworks/\($v)/subnets/\($s)"))
    and (if $p == "yes" then ($c.publicIPAddress.id // "") != "" else ($c.publicIPAddress.id // "") == "" end)' <<<"$nic" >/dev/null
}

tf25_jump_ip() { az network public-ip show -g "rg-$PREFIX-shared" -n "pip-$PREFIX-jump" --query ipAddress -o tsv; }
tf25_web_ip() { az vm list-ip-addresses -g "rg-$PREFIX-dev" -n "vm-$PREFIX-web-dev-$1" --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv; }
tf25_jump_pid() { az vm show -g "rg-$PREFIX-shared" -n "vm-$PREFIX-jump" --query identity.principalId -o tsv; }

# tf25_ssh <host> [via jump ip] -- <command>: run <command> as azureuser with the lab key, through
# the jump host when given. Host keys aren't recorded: VMs come and go with pause/resume.
tf25_ssh() {
  local host=$1 via=$2
  shift 3
  local -a o=(-i "$TF25_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
  if [[ -n "$via" ]]; then
    ssh "${o[@]}" -o "ProxyCommand=ssh ${o[*]} -W %h:%p $TF25_USER@$via" "$TF25_USER@$host" "$@"
  else
    # shellcheck disable=SC2029 # the command is meant to run on the VM as given
    ssh "${o[@]}" "$TF25_USER@$host" "$@"
  fi
}
export -f appenv_kv_id appenv_kv_name role_on tf25_vm tf25_jump_ip tf25_web_ip tf25_jump_pid tf25_ssh

check_code "the modules repo has linux-vm: Ubuntu 24.04, SSH key only" \
  'm="${MODULES_DIR:-}/linux-vm" && grep -qsE "^resource[[:space:]]+\"azurerm_linux_virtual_machine\"" "$m"/*.tf && grep -qsE "^[[:space:]]*admin_ssh_key[[:space:]]*\{" "$m"/*.tf && grep -qsF "ubuntu-24_04-lts" "$m"/*.tf && ! grep -qsE "^[[:space:]]*(disable_password_authentication[[:space:]]*=[[:space:]]*false|admin_password[[:space:]]*=)" "$m"/*.tf' \
  "write $MODULES_DIR/linux-vm/main.tf: azurerm_linux_virtual_machine from ubuntu-24_04-lts with an admin_ssh_key block, no admin_password, password authentication off"

check_code "CHANGELOG.md has a 2.2.0 entry for linux-vm" \
  'c="${MODULES_DIR:-}/CHANGELOG.md" && grep -qE "^#+[^0-9]*v?2\.2\.0" "$c" && grep -qF linux-vm "$c"' \
  "add a \"## 2.2.0\" entry to $MODULES_REPO/CHANGELOG.md that names the new linux-vm module"

check_code "shared and env-dev build their VMs with linux-vm by tag; shared opens SSH in an NSG rule" \
  'grep -rqsE "$TF25_SRC" terraform/shared --include="*.tf" && grep -rqsE "$TF25_SRC" terraform/env-dev --include="*.tf" && grep -rqsE "^resource[[:space:]]+\"azurerm_network_security_rule\"" terraform --include="*.tf"' \
  "terraform/shared (jump) and terraform/env-dev (web) need module sources \"git::https://github.com/$GH_OWNER/$MODULES_REPO.git//linux-vm?ref=v2.2.0\", plus an azurerm_network_security_rule for SSH on nsg-$PREFIX-hub-runner"

check_code "learner_ip is a sensitive variable; the workflow passes the LEARNER_IP secret and the SSH_PUBLIC_KEY variable" \
  'b="$(find terraform -name "*.tf" -not -path "*/.terraform/*" -exec awk "/^variable[[:space:]]+\"learner_ip\"/ { on = 1 } on { print } on && /^}/ { on = 0 }" {} +)" && grep -qE "sensitive[[:space:]]*=[[:space:]]*true" <<<"$b" && ! grep -qE "^[[:space:]]*default[[:space:]]*=" <<<"$b" && grep -qE "^[[:space:]]*TF_VAR_learner_ip:[[:space:]]*\"?\\$\\{\\{[[:space:]]*secrets\.LEARNER_IP[[:space:]]*\\}\\}" .github/workflows/terraform.yml && grep -qE "^[[:space:]]*TF_VAR_ssh_public_key:[[:space:]]*\"?\\$\\{\\{[[:space:]]*vars\.SSH_PUBLIC_KEY[[:space:]]*\\}\\}" .github/workflows/terraform.yml' \
  "declare variable \"learner_ip\" with sensitive = true and no default, and set TF_VAR_learner_ip: \${{ secrets.LEARNER_IP }} and TF_VAR_ssh_public_key: \${{ vars.SSH_PUBLIC_KEY }} in the workflow env"

check_code "outputs jump_public_ip and web_private_ips; no private key in the repo" \
  'grep -rqsE "^output[[:space:]]+\"jump_public_ip\"" terraform/shared --include="*.tf" && grep -rqsE "^output[[:space:]]+\"web_private_ips\"" terraform/env-dev --include="*.tf" && ! grep -rqsIlE "BEGIN (OPENSSH|RSA|EC|DSA)? ?PRIVATE KEY" --exclude-dir=.git --exclude-dir=.terraform .' \
  "add output \"jump_public_ip\" to terraform/shared and output \"web_private_ips\" to terraform/env-dev; a private key must never be committed (it stays in ~/.ssh/${PREFIX}_lab)"

check "tag v2.2.0 in $TF25_MODS contains linux-vm" \
  'gh api "repos/$TF25_MODS/contents/linux-vm?ref=v2.2.0" --jq ".[].name" | grep -c "\.tf$" >/dev/null' \
  "tag the release after CI is green and push it: git tag -a v2.2.0 -m \"linux-vm\" && git push origin v2.2.0"

check "vm-$PREFIX-jump: $TF25_SIZE, Ubuntu 24.04, SSH key only, role=jump env=hub, in snet-runner with a public IP" \
  'tf25_vm "rg-$PREFIX-shared" "vm-$PREFIX-jump" jump hub "vnet-$PREFIX-hub" snet-runner yes' \
  "expected vm-$PREFIX-jump in rg-$PREFIX-shared: size $TF25_SIZE, Canonical ubuntu-24_04-lts, password authentication off with an SSH key, tags role=jump and env=hub, NIC in vnet-$PREFIX-hub/snet-runner with pip-$PREFIX-jump"

check "pip-$PREFIX-jump is a Standard, static public IP" \
  'az network public-ip show -g "rg-$PREFIX-shared" -n "pip-$PREFIX-jump" -o json | jq -e ".sku.name == \"Standard\" and .publicIPAllocationMethod == \"Static\" and (.ipAddress // \"\") != \"\"" >/dev/null' \
  "expected public IP pip-$PREFIX-jump in rg-$PREFIX-shared, SKU Standard, allocation Static, attached to the jump VM's NIC"

check "vm-$PREFIX-web-dev-1 and -2: $TF25_SIZE, Ubuntu 24.04, SSH key only, role=web env=dev, in snet-app, no public IP" \
  'tf25_vm "rg-$PREFIX-dev" "vm-$PREFIX-web-dev-1" web dev "vnet-$PREFIX-dev" snet-app no && tf25_vm "rg-$PREFIX-dev" "vm-$PREFIX-web-dev-2" web dev "vnet-$PREFIX-dev" snet-app no' \
  "expected vm-$PREFIX-web-dev-1 and vm-$PREFIX-web-dev-2 in rg-$PREFIX-dev: size $TF25_SIZE, Canonical ubuntu-24_04-lts, SSH key only, tags role=web and env=dev, NIC in vnet-$PREFIX-dev/snet-app, no public IP"

check "nsg-$PREFIX-hub-runner allows SSH only from $LEARNER_IP/32" \
  'az network nsg rule list -g "rg-$PREFIX-hub" --nsg-name "nsg-$PREFIX-hub-runner" -o json | jq -e "$TF25_NSG_JQ" >/dev/null' \
  "nsg-$PREFIX-hub-runner needs an inbound Allow rule for TCP 22 from $LEARNER_IP/32 and no other rule that opens 22. Your IP changed? ./lab.sh init --refresh-ip, update the repo secret LEARNER_IP, re-run the pipeline"

check "the jump VM's identity: Reader on the subscription, Key Vault Secrets User on both vaults" \
  'pid="$(tf25_jump_pid)" && role_on "$pid" "/subscriptions/$SUBSCRIPTION_ID" Reader && role_on "$pid" "$(appenv_kv_id dev)" "Key Vault Secrets User" && role_on "$pid" "$(appenv_kv_id prod)" "Key Vault Secrets User"' \
  "vm-$PREFIX-jump needs a system-assigned identity with Reader on /subscriptions/$SUBSCRIPTION_ID and Key Vault Secrets User on $(appenv_kv_name dev) and $(appenv_kv_name prod)"

# A secret's value can't be read back: this proves the secret exists (and no variable leaks the
# IP into public logs). The NSG check above proves the value, end to end.
check "repo secret LEARNER_IP exists; repo variable SSH_PUBLIC_KEY matches ~/.ssh/${PREFIX}_lab.pub" \
  '[[ "$(gh api "repos/$TF25_LIVE/actions/secrets/LEARNER_IP" --jq .name)" == LEARNER_IP ]] && ! gh api "repos/$TF25_LIVE/actions/variables/LEARNER_IP" >/dev/null 2>&1 && k="$(gh api "repos/$TF25_LIVE/actions/variables/SSH_PUBLIC_KEY" --jq .value)" && [[ -f "$TF25_KEY.pub" ]] && [[ "$(awk "{print \$1, \$2}" <<<"$k")" == "$(awk "{print \$1, \$2}" "$TF25_KEY.pub")" ]]' \
  "gh secret set LEARNER_IP -R $TF25_LIVE --body $LEARNER_IP (no repo variable of that name) and gh variable set SSH_PUBLIC_KEY -R $TF25_LIVE < ~/.ssh/${PREFIX}_lab.pub"

check "ssh with ~/.ssh/${PREFIX}_lab reaches the jump VM" \
  'ip="$(tf25_jump_ip)" && [[ -n "$ip" ]] && tf25_ssh "$ip" "" -- true' \
  "ssh -i ~/.ssh/${PREFIX}_lab $TF25_USER@<jump_public_ip> failed: is the key pair the one in SSH_PUBLIC_KEY, and LEARNER_IP your current IP?"

check "vm-$PREFIX-web-dev-1 is reachable through the jump VM and reaches the Ubuntu archive" \
  'j="$(tf25_jump_ip)" && w="$(tf25_web_ip 1)" && [[ -n "$j" && -n "$w" ]] && tf25_ssh "$w" "$j" -- curl -fsS -o /dev/null --max-time 15 http://archive.ubuntu.com/ubuntu/' \
  "ssh -J $TF25_USER@<jump_public_ip> $TF25_USER@<web private IP> failed, or the web VM can't reach archive.ubuntu.com (apt needs outbound internet)"

check "the latest terraform run on main succeeded" \
  'ci_main_green "$TF25_LIVE"' \
  "the newest completed terraform.yml run on main in $TF25_LIVE is not green"
