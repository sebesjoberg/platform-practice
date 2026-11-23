# tf-28 hints

Docs:
- State locking: https://developer.hashicorp.com/terraform/language/state/locking
- `terraform force-unlock`: https://developer.hashicorp.com/terraform/cli/commands/force-unlock
- The `azurerm` backend (locking with blob leases): https://developer.hashicorp.com/terraform/language/backend/azurerm
- Blob leases: https://learn.microsoft.com/rest/api/storageservices/lease-blob

Traps:
- **How the azurerm backend locks.** It takes an infinite *lease* on the state blob, with the
  lock ID as the lease ID, and writes the lock details (who, when, which operation) as the blob
  metadata entry `terraformlockid` (base64 JSON). A run that dies between lock and unlock (a
  killed runner, a closed laptop) leaves both behind. Nothing expires them.
- **Read the error.** `Error acquiring the state lock` comes with `Lock Info:` and its `ID`.
  That's the ID `force-unlock` wants, and the lease ID too.
- **Stale or busy?** A lock held by a running job is correct. Before you unlock, check the
  Actions tab (terraform.yml *and* drift.yml) and ask whoever's name is in `Who`. Unlocking
  under a running apply lets two runs write the same state.
- **`force-unlock` needs the backend, not the variables:** run `terraform init` first, then
  `terraform force-unlock <ID>` and answer `yes` (or add `-force`). It removes the metadata entry
  and releases the lease.
- **Breaking the lease works too:** `az storage blob lease break --auth-mode login ... -b env-dev.tfstate`
  frees the blob, but leaves the stale lock details in the metadata until the next run
  overwrites them. `force-unlock` is the tool that knows both halves.
- **Why `-lock-timeout=5m` in the pipeline didn't help:** it waits for a lock to be released,
  which a stale lock never is.
- **Your Azure role matters.** Leases are data-plane operations: you need `Storage Blob Data
  Contributor` on the state account (bootstrap gave it to you in tf-03), not just Owner.
