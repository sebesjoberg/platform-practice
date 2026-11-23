# an-20 checks (sourced by the grader; cwd = LIVE_DIR)

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/ansible.sh"

export AN20_REPO="$GH_OWNER/$LIVE_REPO" AN20_PB=ansible/compliance.yml AN20_JSON=ansible/reports/compliance.json

# an20_playbook: compliance.yml reads package versions, sshd's effective settings, the units'
# sandboxing score and the certificate's expiry, and writes reports/compliance.json.
an20_playbook() {
  local f=$AN20_PB
  [[ -f "$f" ]] || { echo "no $f"; return 1; }
  grep -qE "package_facts|dpkg-query|apt list" "$f" || { echo "no package versions"; return 1; }
  grep -qE "sshd -T" "$f" || { echo "no sshd -T"; return 1; }
  grep -qE "systemd-analyze security" "$f" || { echo "no systemd-analyze security"; return 1; }
  grep -qE "openssl x509|x509_info|enddate|not_after" "$f" || { echo "no certificate expiry"; return 1; }
  grep -qE "compliance\.json" "$f" || { echo "it doesn't write reports/compliance.json"; return 1; }
}

# an20_ci_job: a runner job (with the fork guard) runs compliance.yml and uploads the report with
# actions/upload-artifact as compliance-report; the report directory is gitignored.
an20_ci_job() {
  local j body ok=0
  while IFS= read -r j; do
    body="$(an_wf_job "$j")"
    grep -qE "compliance\.yml" <<<"$body" || continue
    grep -qE "uses:[[:space:]]*actions/upload-artifact@" <<<"$body" && grep -qE "name:[[:space:]]*.?compliance-report" <<<"$body" &&
      an_wf_fork_guard "$j" && ok=1
  done < <(an_wf_runner_jobs)
  [[ $ok -eq 1 ]] || { echo "no runner job that runs compliance.yml and uploads compliance-report"; return 1; }
  grep -qsxE "[[:space:]]*/?(ansible/)?reports/?[[:space:]]*" ansible/.gitignore .gitignore || { echo "reports/ is not gitignored"; return 1; }
}

# an20_local_report: compliance.yml, run here (read-only on the hosts), writes
# reports/compliance.json with the three VMs: sshd refuses root logins everywhere, the web VMs
# report acme-hello's exposure (below 5.0) and their certificate's expiry, packages are listed.
an20_local_report() {
  rm -f "$AN20_JSON"
  an_run ansible-playbook compliance.yml >/dev/null 2>&1 || { echo "ansible-playbook compliance.yml failed"; return 1; }
  [[ -s "$AN20_JSON" ]] || { echo "no $AN20_JSON"; return 1; }
  jq -e --arg j "vm-$PREFIX-jump" --arg w1 "vm-$PREFIX-web-dev-1" --arg w2 "vm-$PREFIX-web-dev-2" '
    .hosts as $h
    | ([$j, $w1, $w2] | all(. as $n | $h | has($n)))
    and ([$j, $w1, $w2] | all(. as $n | $h[$n].sshd.permitrootlogin == "no" and ($h[$n].packages["openssh-server"] // "") != ""))
    and ([$w1, $w2] | all(. as $n | ($h[$n].units["acme-hello.service"] | type == "number" and . < 5)
      and (($h[$n].tls_not_after // "") | length > 0)))' "$AN20_JSON" >/dev/null ||
    { echo "$AN20_JSON lacks hosts or fields (hosts.<vm>.sshd, .packages, .units, .tls_not_after)"; return 1; }
}

# an20_artifact: a run of ansible.yml uploaded an artifact compliance-report that hasn't expired.
an20_artifact() {
  gh api "repos/$AN20_REPO/actions/artifacts?name=compliance-report&per_page=10" \
    --jq '[.artifacts[] | select(.expired | not)] | length' | grep -qvx 0
}
export -f an20_playbook an20_ci_job an20_local_report an20_artifact

check_code "compliance.yml: package versions, sshd -T, systemd-analyze security, certificate expiry, reports/compliance.json" \
  'an20_playbook' \
  "write ansible/compliance.yml: package_facts, sshd -T, systemd-analyze security <unit>, openssl x509 -enddate on the TLS certificate, and a play on localhost that writes reports/compliance.json (and a Markdown version)"

check_code "ansible.yml: a runner job runs compliance.yml and uploads compliance-report; reports/ is gitignored" \
  'an20_ci_job' \
  "add job compliance (schedule and workflow_dispatch task=compliance, [self-hosted, acme-jump], the fork guard): ansible-playbook compliance.yml --limit env_dev:env_hub, then actions/upload-artifact@v4 with name: compliance-report; add reports/ to ansible/.gitignore"

an20_timeout="${GRADE_TIMEOUT:-}"
GRADE_TIMEOUT=300
check "ansible-playbook compliance.yml (here) writes reports/compliance.json with the three VMs and their data" \
  'an20_local_report' \
  "cd ansible && ansible-playbook compliance.yml must write reports/compliance.json: {\"hosts\": {\"vm-$PREFIX-web-dev-1\": {\"sshd\": {...}, \"packages\": {...}, \"units\": {\"acme-hello.service\": 1.9}, \"tls_not_after\": \"...\"}, ...}}"
GRADE_TIMEOUT="$an20_timeout"

check "a run of ansible.yml uploaded the artifact compliance-report" \
  'an20_artifact' \
  "gh workflow run ansible.yml -f task=compliance, wait for it (gh run watch), then gh api repos/$AN20_REPO/actions/artifacts?name=compliance-report"
