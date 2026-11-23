# tf-27 solution

## What happened

Someone changed two things in the portal:

- the `owner` tag of `rg-{{PREFIX}}-dev` became `ops-oncall` (env-dev's plan shows it: an in-place
  update of `module.spoke.azurerm_resource_group.this`);
- an inbound rule `AllowAll-Temp` (any protocol, any source, any port) on
  `nsg-{{PREFIX}}-dev-app`. **No plan shows it**: the spoke module's NSGs have no inline rules, the
  provider treats `security_rule` as optional and computed, and Terraform never plans away a rule
  it was never told about.

## Approach

1. Write `.github/workflows/drift.yml` (below), open a PR, merge.
2. `gh workflow run drift.yml && gh run watch`: env-dev drifted, the run fails, and an issue
   labelled `drift` appears with env-dev's plan.
3. Put the tag back by applying the code: `gh workflow run terraform.yml -f stacks=env-dev`.
4. Remove the rule nobody owns: `az network nsg rule delete -g rg-{{PREFIX}}-dev --nsg-name nsg-{{PREFIX}}-dev-app -n AllowAll-Temp`.
5. `gh workflow run drift.yml`: green, and the issue is closed.

## The workflow

Its full text is in the reference (`.github/workflows/drift.yml`). The core of it:

```yaml
on:
  schedule:
    - cron: "17 5 * * 1-5"
  workflow_dispatch:

jobs:
  detect:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
      issues: write
    steps:
      # checkout, Find stacks (stacks.sh all), setup-terraform (terraform_wrapper: false), azure/login
      - name: terraform plan -detailed-exitcode
        id: plan
        env:
          STACKS: ${{ steps.stacks.outputs.list }}
        run: |
          drifted="" failed=""
          for s in $STACKS; do
            rc=0
            terraform -chdir="terraform/$s" init -input=false -no-color >"$RUNNER_TEMP/$s.log" 2>&1 || rc=1
            if [ "$rc" -eq 0 ]; then
              terraform -chdir="terraform/$s" plan -input=false -no-color -lock-timeout=5m \
                -detailed-exitcode >>"$RUNNER_TEMP/$s.log" 2>&1 || rc=$?
            fi
            case "$rc" in
              0) ;;
              2) drifted="$drifted $s" ;;   # and append the plan to $RUNNER_TEMP/drift.md
              *) failed="$failed $s" ;;
            esac
          done
          echo "drifted=${drifted# }" >> "$GITHUB_OUTPUT"
          echo "failed=${failed# }" >> "$GITHUB_OUTPUT"
      - name: Open or update the drift issue
        if: steps.plan.outputs.drifted != ''
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh label create drift --force
          n="$(gh issue list --label drift --state open --json number --jq '.[0].number // empty')"
          if [ -n "$n" ]; then gh issue comment "$n" --body-file "$RUNNER_TEMP/drift.md"
          else gh issue create --label drift --title "Drift detected" --body-file "$RUNNER_TEMP/drift.md"; fi
      - name: Close the drift issue
        if: steps.plan.outputs.drifted == '' && steps.plan.outputs.failed == ''
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          for n in $(gh issue list --label drift --state open --json number --jq '.[].number'); do
            gh issue close "$n" --comment "Clean again."
          done
      - name: Fail on drift or errors
        if: steps.plan.outputs.drifted != '' || steps.plan.outputs.failed != ''
        run: exit 1
```

Workflow-level `env` is the same as `terraform.yml`'s (`ARM_*`, `TF_VAR_*`, `STACK_ORDER`), and a
`concurrency` group keeps two drift runs from overlapping.

## Verify

```bash
gh run list --workflow drift.yml --limit 3
gh issue list --label drift --state all
az group show -n rg-{{PREFIX}}-dev --query tags.owner -o tsv          # {{OWNER_TAG}}
az network nsg rule list -g rg-{{PREFIX}}-dev --nsg-name nsg-{{PREFIX}}-dev-app -o table   # empty
```

## Going further

To make Terraform own an NSG's rules, declare them: `security_rule = []` on the NSG makes an
empty rule list authoritative, so any rule added by hand shows up as drift. Inline rules and
standalone `azurerm_network_security_rule` resources must not be mixed on one NSG, which is why
the hub's NSGs (tf-25, the Ansible track) can't do that.
