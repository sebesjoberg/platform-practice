# an-08 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

# an08_thumbprint_ok: from the jump host, each web VM's private IP serves (on 443, SNI
# acme-web.internal) the certificate whose SHA-1 thumbprint Key Vault reports for web-tls.
an08_thumbprint_ok() {
  local want
  local -a ips
  want="$(az keyvault certificate show --vault-name "$(an_kv_name)" -n web-tls --query x509ThumbprintHex -o tsv)"
  [[ -n "$want" ]] || return 1
  mapfile -t ips < <(an_group_ips role_web)
  [[ ${#ips[@]} -ge 2 ]] || return 1
  an_probe role_jump 1 tls-thumbprint.sh "$want" "${ips[*]}"
}
export -f an08_thumbprint_ok

check_code "the certificate web-tls is read with the azure.azcollection.azure_keyvault_secret lookup" \
  'files="$(grep -rlE --exclude-dir=.venv --exclude-dir=collections --exclude-dir=.ansible "azure\.azcollection\.azure_keyvault_secret" ansible)" && grep -qF "web-tls" $files' \
  "look up the certificate's secret: lookup('azure.azcollection.azure_keyvault_secret', 'web-tls', vault_url=...): a Key Vault certificate's key and certificate are in the secret of the same name"

check_code "the nginx template listens on 443 with ssl" \
  'grep -rqE "listen[[:space:]]+([^;]*:)?443[[:space:]]+[^;]*ssl" ansible/roles/nginx/templates' \
  "add listen 443 ssl (with ssl_certificate and ssl_certificate_key) to the server in roles/nginx/templates, keeping listen 80"

check_code "role nginx writes the private key without group/other permissions (0600, 0400, u=rw,go=) and with no_log" \
  't=ansible/roles/nginx/tasks && grep -rqE "mode:[[:space:]]*.?(0?[0-7]00|u=[rwx]*,(go|og)=|u=[rwx]*,g=,o=|u=[rwx]*,o=,g=).?[[:space:]]*$" "$t" && grep -rqE "no_log:[[:space:]]*.?true" "$t"' \
  "in roles/nginx/tasks: write the key with a mode without group/other bits (\"0600\", \"0400\", u=rw,go=), owner root, and no_log: true; the certificate can be 0644"

an08_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=180
check "from the jump host, both web VMs serve web-tls on 443 (thumbprint = Key Vault's)" \
  'an08_thumbprint_ok' \
  "on the jump host: openssl s_client -connect <web private IP>:443 -servername acme-web.internal | openssl x509 -noout -fingerprint -sha1 must match az keyvault certificate show --vault-name $(an_kv_name) -n web-tls --query x509ThumbprintHex (renewed in Key Vault? run site.yml)"

check "both web VMs: nginx listens on 443 and its private keys are root-owned, no group/other permissions" \
  'an_probe role_web 2 tls-key.sh' \
  "sudo nginx -T on each web VM must show listen 443 ssl, and every ssl_certificate_key file must be owned by root with no group/other permissions (0600 or 0400)"

GRADE_TIMEOUT=900
check "molecule test passes for role nginx (now with TLS)" \
  'an_molecule_test nginx' \
  "cd ansible/roles/nginx && molecule test must pass; converge needs a throwaway certificate in place of the Key Vault one"

GRADE_TIMEOUT=480
check "a second run of site.yml changes nothing: changed=0 on every host" \
  'an_second_run' \
  "cd ansible && ansible-playbook site.yml twice: the second PLAY RECAP must show changed=0 unreachable=0 failed=0 for every VM"
GRADE_TIMEOUT="$an08_timeout"
