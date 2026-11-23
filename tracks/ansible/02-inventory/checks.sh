# an-02 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

# Files under ansible/ that set ansible_ssh_common_args (group_vars, host_vars or the inventory).
an02_ssh_args_files() {
  grep -rlE --include='*.yml' --include='*.yaml' --include='*.ini' \
    --exclude-dir=.venv --exclude-dir=collections --exclude-dir=.ansible \
    "ansible_ssh_common_args" ansible 2>/dev/null
}

# The "no IP" part of the second check_code ignores loopback and 0.0.0.0: an-09 puts
# nginx_proxy_pass: http://127.0.0.1:8080 into the same group_vars file. Only a VM's address counts.

# an02_graph_ok: one inventory load (each one imports the Azure SDK and calls az). Parses
# `ansible-inventory --graph` into "group host" pairs and requires the lab VMs in their groups.
an02_graph_ok() {
  local g pairs p
  g="$(an_run ansible-inventory --graph)" || return 1
  pairs="$(awk '{ if (match($0, /--@[^:]+:/)) { g = substr($0, RSTART + 3, RLENGTH - 4) }
    else if (match($0, /\|--[^ ]+$/)) { print g, substr($0, RSTART + 3) } }' <<<"$g")"
  for p in "role_web vm-$PREFIX-web-dev-1" "role_web vm-$PREFIX-web-dev-2" \
    "env_dev vm-$PREFIX-web-dev-1" "env_dev vm-$PREFIX-web-dev-2" "role_jump vm-$PREFIX-jump"; do
    grep -qxF "$p" <<<"$pairs" || return 1
  done
}

# an02_jump_ip_dynamic: the jump host's real public IP appears in no file under ansible/, and the
# effective ansible_ssh_common_args of a web host contains it (templated from the inventory).
# `debug` runs on the control node: no connection to the VM.
an02_jump_ip_dynamic() {
  local ip
  ip="$(an_run ansible-inventory --host "vm-$PREFIX-jump" | jq -r '.public_ipv4_address[0] // empty')"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  ! grep -rqF --exclude-dir=.venv --exclude-dir=collections --exclude-dir=.ansible "$ip" ansible || return 1
  an_run ansible "vm-$PREFIX-web-dev-1" -m ansible.builtin.debug -a var=ansible_ssh_common_args | grep -qF "$ip"
}
export -f an02_ssh_args_files an02_graph_ok an02_jump_ip_dynamic

check_code "ansible/inventory/azure_rm.yml: azure_rm plugin, CLI auth, keyed groups on the role and env tags" \
  'f=ansible/inventory/azure_rm.yml && grep -qE "^plugin:[[:space:]]*.?azure\.azcollection\.azure_rm" "$f" && grep -qE "^auth_source:[[:space:]]*.?cli" "$f" && grep -qE "^keyed_groups:" "$f" && grep -qE "prefix:[[:space:]]*.?role.?[[:space:]]*$" "$f" && grep -qE "prefix:[[:space:]]*.?env.?[[:space:]]*$" "$f" && grep -qE "tags(\.role|\[.role.\])" "$f" && grep -qE "tags(\.env|\[.env.\])" "$f"' \
  "write ansible/inventory/azure_rm.yml with plugin: azure.azcollection.azure_rm, auth_source: cli and keyed_groups with prefix role (key tags.role) and prefix env (key tags.env), so the groups are role_web, role_jump, env_dev, env_hub"

check_code "the web hosts SSH through the jump host, its IP looked up at run time (no IP in the files)" \
  'files="$(an02_ssh_args_files)" && [[ -n "$files" ]] && grep -qE "Proxy(Command|Jump)|(^|[^[:alnum:]_-])-J[[:space:]=]" $files && grep -qF "{{" $files && { ips="$(grep -hoE "([0-9]{1,3}\.){3}[0-9]{1,3}" $files)"; [[ -z "$ips" ]] || ! grep -qvE "^(127\.[0-9.]+|0\.0\.0\.0)$" <<<"$ips"; }' \
  "set ansible_ssh_common_args for the web hosts (e.g. ansible/inventory/group_vars/role_web.yml): a ProxyCommand/ProxyJump through the jump host whose public IP is templated from the inventory (the jump host's hostvars), never a literal IP"

check_code "Ansible logs in as azureuser with ~/.ssh/${PREFIX}_lab" \
  'grep -rqsE --exclude-dir=.venv --exclude-dir=collections "(ansible_user:[[:space:]]*.?azureuser|remote_user[[:space:]]*=[[:space:]]*azureuser)" ansible && grep -rqsE --exclude-dir=.venv --exclude-dir=collections "(ansible_ssh_private_key_file:|private_key_file[[:space:]]*=).*\.ssh/${PREFIX}_lab.?[[:space:]]*$" ansible' \
  "set ansible_user: azureuser and ansible_ssh_private_key_file: ~/.ssh/${PREFIX}_lab (e.g. in ansible/inventory/group_vars/all.yml)"

check_code "ansible/ansible.cfg uses the dynamic inventory" \
  'grep -qE "^[[:space:]]*inventory[[:space:]]*=[[:space:]]*\S*inventory" ansible/ansible.cfg' \
  "add inventory = inventory/azure_rm.yml to [defaults] in ansible/ansible.cfg, so plain ansible / ansible-playbook use it"

# Each inventory load imports the Azure SDK and runs several az calls: give these checks room.
an02_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=180
check "ansible-inventory --graph: role_web and env_dev hold both web VMs, role_jump the jump VM" \
  'an02_graph_ok' \
  "cd ansible && ansible-inventory --graph must show @role_web and @env_dev with vm-$PREFIX-web-dev-1/-2 and @role_jump with vm-$PREFIX-jump (hostnames = VM names). VMs running (./lab.sh resume)? az logged in to the lab subscription?"

check "the jump host's public IP is in no file, and the web hosts' SSH args get it from the inventory" \
  'an02_jump_ip_dynamic' \
  "the public IP of vm-$PREFIX-jump (ansible-inventory --host vm-$PREFIX-jump) must not appear in any file under ansible/, and ansible vm-$PREFIX-web-dev-1 -m debug -a var=ansible_ssh_common_args must show it: template it from the jump host's hostvars"

check "ansible all -m ping reaches the three VMs (the web VMs through the jump host)" \
  'n="$(an_host_count)" && [[ "${n:-0}" -ge 3 ]] && an_run ansible all -m ansible.builtin.ping' \
  "cd ansible && ansible all -m ping failed or found fewer than 3 hosts. ssh -i ~/.ssh/${PREFIX}_lab azureuser@<jump public IP> must work first (IP changed? ./lab.sh init --refresh-ip, update the LEARNER_IP secret, re-run the shared stack)"
GRADE_TIMEOUT="$an02_timeout"
