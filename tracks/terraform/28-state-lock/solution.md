# tf-28 solution

## Diagnose

```bash
cd "$LIVE_DIR/terraform/env-dev"
terraform init
terraform plan -lock-timeout=10s
```

```
Error: Error acquiring the state lock
...
Lock Info:
  ID:        3f6c1d0e-....
  Path:      tfstate/env-dev.tfstate
  Operation: OperationTypeApply
  Who:       sam@build-agent-07
  Version:   1.17.2
  Created:   ...
```

Nobody holds it for a reason:

```bash
gh run list --status in_progress            # terraform.yml and drift.yml: nothing running
gh run list --workflow terraform.yml --limit 5
az storage blob show --auth-mode login --account-name st{{PREFIX}}tfstate{{SUFFIX}} \
  -c tfstate -n env-dev.tfstate --query properties.lease
# {"duration": "infinite", "state": "leased", "status": "locked"}
```

An infinite lease from an agent that no longer exists, hours old, and no run in progress: stale.

## Fix

```bash
terraform force-unlock 3f6c1d0e-....        # yes
az storage blob show --auth-mode login --account-name st{{PREFIX}}tfstate{{SUFFIX}} \
  -c tfstate -n env-dev.tfstate --query properties.lease.state -o tsv   # available
```

(Equivalent, but leaves the stale details in the metadata until the next lock:
`az storage blob lease break --auth-mode login --account-name st{{PREFIX}}tfstate{{SUFFIX}} -c tfstate -b env-dev.tfstate`.)

## Verify in CI

```bash
gh workflow run terraform.yml -f stacks=env-dev
gh run watch "$(gh run list --workflow terraform.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

## Afterwards

Write two lines in the team channel: what held the lock, how you knew it was stale, the ID you
released. A force-unlock is a change to shared state; it deserves the same trail as a merge.
