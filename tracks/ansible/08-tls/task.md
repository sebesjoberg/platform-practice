---
id: an-08
title: TLS from a Key Vault certificate
target_minutes: 20
requires: [tf-25, an-07]
---
# an-08 TLS from a Key Vault certificate

Security wants TLS on every hop, the internal ones too, and no private key on anybody's laptop
or in any repo. The platform team owns certificates in Key Vault: `./lab.sh next` granted you
**Key Vault Certificates Officer** on `kv-{{PREFIX}}-dev-{{SUFFIX}}` and created a self-signed
certificate `web-tls` there from a Key Vault policy: subject `CN=acme-web.internal`, SANs for
`acme-web.internal`, `vm-{{PREFIX}}-web-dev-1` and `vm-{{PREFIX}}-web-dev-2`, 12 months,
PEM content type, renewed by Key Vault 30 days before expiry. Your job: serve it.

## Deliverables

- [ ] nginx on both web VMs serves HTTPS on 443 with `web-tls`; port 80 keeps serving (the load
      balancer in an-10 checks and forwards on 80 inside the network). TLS 1.2 and 1.3 only.
- [ ] The key and the certificate come from Key Vault at run time, through the same lookup and
      the same auth variable as in an-07. (Where is a certificate's private key in Key Vault?
      Not in the certificate object.)
- [ ] On the VMs: private key owned by root, mode `0600`, written with `no_log`; certificate
      `0644`. When Key Vault renews the certificate, the next run deploys it and reloads nginx.
- [ ] Role `nginx` stays usable without Key Vault: TLS is switched on and fed through role
      variables. The Molecule scenario converges with a throwaway self-signed certificate and
      verifies 443.
- [ ] Lint-clean; a second `site.yml` run reports `changed=0`.

## Done when

On the jump host, `openssl s_client -connect <web private IP>:443 -servername acme-web.internal`
piped into `openssl x509 -noout -fingerprint -sha1` shows, for both web VMs, the thumbprint that
`az keyvault certificate show --vault-name kv-{{PREFIX}}-dev-{{SUFFIX}} -n web-tls --query x509ThumbprintHex -o tsv`
prints (without the colons), and `./lab.sh grade` passes.

After `./lab.sh pause` / `resume` the vault is new: `tracks/ansible/lib/keyvault-prereqs.sh` from
the lab directory restores your role and issues a new certificate; then run `site.yml`.

Target: 20 minutes.
