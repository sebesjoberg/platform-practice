# platform-practice

An auto-graded Terraform + Ansible on Azure practice lab (full README coming in a later task).

## Handover from the Terraform track to the Ansible track

Do the Terraform track up to tf-25 first. Its end state is what the Ansible track builds on:

- `vm-<prefix>-jump` in `rg-<prefix>-shared` with the public IP `pip-<prefix>-jump`, SSH open
  only to your IP (repo secret `LEARNER_IP`), and a system-assigned identity with Reader on the
  subscription and Key Vault Secrets User on both vaults.
- `vm-<prefix>-web-dev-1` and `vm-<prefix>-web-dev-2` in `rg-<prefix>-dev`, private only,
  reached through the jump host.
- All three: Ubuntu 24.04 LTS, user `azureuser`, SSH key `~/.ssh/<prefix>_lab` (never in a
  repo), tags `role` (`jump`/`web`) and `env` (`hub`/`dev`) for the dynamic inventory.

After tf-25 the tracks can be done in any order. The day-two tasks tf-26 … tf-31 (import,
drift, a state lock, the observability stack, the azurerm 5 upgrade, team onboarding) never
change the VMs, their tags, the jump host's IP and port 22 rule, the SSH key, the jump
identity's roles or the vaults. `./lab.sh next ansible` checks for this state,
and `./lab.sh catchup tf-25` builds it. When your IP changes: `./lab.sh init --refresh-ip`, then
follow what it prints (update the repo secret `LEARNER_IP`, re-run the pipeline for
`shared`). Details: the "Handover to the Ansible track" section of
`tracks/terraform/25-vms-handover/task.md`.
