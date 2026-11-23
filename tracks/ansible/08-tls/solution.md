# an-08 solution

## Approach

The certificate's secret (`web-tls`, PEM: key then certificate) is looked up in the inventory
like an-07's secret and handed to role `nginx` as `nginx_tls_pem`, with a separate switch
`nginx_tls: true`. The role reads the bundle once (`set_fact`, `no_log`), splits it into
`/etc/nginx/tls/acme-web.key` (0600, `no_log`) and `acme-web.crt` (0644), then templates
`nginx.conf` with a `listen 443 ssl` that is validated like everything else.

## Code

`ansible/inventory/group_vars/role_web.yml`, added:

```yaml
nginx_tls: true
nginx_tls_pem: >-
  {{ lookup('azure.azcollection.azure_keyvault_secret', 'web-tls',
  vault_url=acme_kv_url, auth_source=acme_kv_auth_source,
  use_msi=(acme_kv_auth_source == 'msi')) }}
```

`roles/nginx/tasks/main.yml`, before the configuration template:

```yaml
- name: TLS key and certificate
  ansible.builtin.import_tasks: tls.yml
  when: nginx_tls
```

`roles/nginx/tasks/tls.yml`:

```yaml
---
- name: Read the TLS bundle
  ansible.builtin.set_fact:
    nginx_tls_bundle: >-
      {{ nginx_tls_pem | replace('\r', '') }}
  no_log: true

- name: Check that the bundle holds a private key and a certificate
  ansible.builtin.assert:
    that:
      - nginx_tls_bundle is search('-----BEGIN [A-Z ]*PRIVATE KEY-----')
      - nginx_tls_bundle is search('-----BEGIN CERTIFICATE-----')
    quiet: true

- name: Create the TLS directory
  ansible.builtin.file:
    path: "{{ nginx_tls_dir }}"
    state: directory
    owner: root
    group: root
    mode: "0755"

- name: Install the private key
  ansible.builtin.copy:
    content: "{{ nginx_tls_bundle | regex_search('(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.+?-----END [A-Z ]*PRIVATE KEY-----') }}\n"
    dest: "{{ nginx_tls_dir }}/{{ nginx_tls_name }}.key"
    owner: root
    group: root
    mode: "0600"
  no_log: true
  notify: Reload nginx

- name: Install the certificate
  ansible.builtin.copy:
    content: "{{ nginx_tls_bundle | regex_findall('(?s)-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----') | join('\n') }}\n"
    dest: "{{ nginx_tls_dir }}/{{ nginx_tls_name }}.crt"
    owner: root
    group: root
    mode: "0644"
  notify: Reload nginx
```

`templates/nginx.conf.j2`, inside the server block:

```nginx
        listen 80 default_server;
{% if nginx_tls %}
        listen 443 ssl default_server;
        ssl_certificate {{ nginx_tls_dir }}/{{ nginx_tls_name }}.crt;
        ssl_certificate_key {{ nginx_tls_dir }}/{{ nginx_tls_name }}.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_session_cache shared:TLS:10m;
        ssl_session_tickets off;
{% endif %}
```

Defaults: `nginx_tls: false`, `nginx_tls_pem: ""`, `nginx_tls_dir: /etc/nginx/tls`,
`nginx_tls_name: acme-web`; `argument_specs.yml` marks `nginx_tls_pem` `no_log: true`.

Molecule `converge.yml`: `pre_tasks` create `/root/molecule-tls.{key,crt}` with
`openssl req -x509 -newkey rsa:2048 -nodes ...` (`creates:`), `slurp` both, and set
`nginx_tls: true` and `nginx_tls_pem` to key + certificate. `verify.yml` adds: `uri` to
`https://127.0.0.1/` (`validate_certs: false`), the served SHA-256 fingerprint equals the test
certificate's, and the key is `root` `0600`.

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
(cd roles/nginx && molecule test)
ansible-lint && ansible-playbook site.yml
az keyvault certificate show --vault-name kv-{{PREFIX}}-dev-{{SUFFIX}} -n web-tls --query x509ThumbprintHex -o tsv
ssh -i ~/.ssh/{{PREFIX}}_lab azureuser@<jump public IP>
#   for ip in <web-1 IP> <web-2 IP>; do
#     openssl s_client -connect $ip:443 -servername acme-web.internal </dev/null 2>/dev/null \
#       | openssl x509 -noout -fingerprint -sha1 -subject -ext subjectAltName; done
ansible-playbook site.yml      # changed=0
```

Commit on a branch, pull request, merge.

## Verify

`./lab.sh grade`. The certificate stays in Key Vault (it renews itself); nothing to clean up.
Clients don't trust a self-signed certificate: `curl -k` or `--cacert` with the `.crt` for tests.
