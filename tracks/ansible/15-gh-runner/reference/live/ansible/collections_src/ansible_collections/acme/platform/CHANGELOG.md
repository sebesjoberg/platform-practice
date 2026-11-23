# Changelog of acme.platform

## 1.1.0

- New role `gh_runner`: a self-hosted GitHub Actions runner as a systemd service under its own
  user, with an ed25519 key for reaching the fleet (generated on the host, never copied).

## 1.0.0

- First release, packaged from the repo's `ansible/roles` and `ansible/library`: roles `base`,
  `app_env`, `acme_hello`, `nginx`, `haproxy` and the module `acme_app_setting`.
