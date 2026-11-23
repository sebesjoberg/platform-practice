# an-08 hints

Docs:
- Key Vault certificates, and the key/secret objects behind each one: https://learn.microsoft.com/en-us/azure/key-vault/certificates/about-certificates
- Exporting a certificate with its private key (the secret, PEM or PFX): https://learn.microsoft.com/en-us/azure/key-vault/certificates/how-to-export-certificate
- nginx HTTPS configuration: https://nginx.org/en/docs/http/configuring_https_servers.html
- Filters `regex_search`, `regex_findall`: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_filters.html#searching-strings-with-regular-expressions

Traps:
- **The certificate object has no private key.** `az keyvault certificate show` (and its `cer`
  field) is the public certificate. The key and certificate together are in the **secret** with
  the same name, `web-tls`: with the PEM content type, a private key block followed by the
  certificate. Your an-07 lookup reads it; Secrets Officer (yours) or Secrets User (the jump
  host's) is enough.
- **Split it, or point both directives at one file.** nginx accepts the same combined PEM for
  `ssl_certificate` and `ssl_certificate_key`, but then the whole file needs `0600`. Splitting
  gives a world-readable certificate and a root-only key. `regex_search` with `(?s)` lets `.`
  cross newlines.
- **Install key and certificate before the configuration.** `validate: nginx -t -c %s` loads
  every file the configuration names; a config that points at a missing key fails validation.
- **A lookup in a variable runs every time the variable is templated**, a `when:` included. A
  separate boolean (`nginx_tls: true`) to switch TLS on, and one `set_fact` (with `no_log`) that
  reads the bundle, keep it to one Key Vault call per host per run.
- **No `\r` surprises:** strip carriage returns from the bundle before splitting, or a Windows
  line ending turns into a changed file on every run.
- **Molecule:** generate a throwaway certificate in the container (`openssl req -x509 ... creates:`
  keeps it idempotent), `slurp` it back and concatenate key and certificate the way Key Vault
  does. `uri` with `validate_certs: false` for 443; compare fingerprints with `openssl`.
- **The thumbprint** Key Vault reports (`x509ThumbprintHex`) is the SHA-1 fingerprint, uppercase,
  without colons.
- **Port 80 stays.** HAProxy (an-10) health-checks plain HTTP on 80; redirecting everything to
  443 would make every backend look broken.
