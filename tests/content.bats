load test_helper

# Track content and track helpers the final review flagged (M3, M4, M7).

setup() { setup_lab; }
teardown() { teardown_lab; }

# --- M7: an_wf_fork_guard (tracks/ansible/lib/ansible.sh) ---------------------------------------

G="github.event.pull_request.head.repo.full_name == github.repository"
PRG="(github.event_name != 'pull_request' || $G)"

# fork_guard "<job if:>" [step if:]: an_wf_fork_guard on job apply of a workflow with that if:.
fork_guard() {
  {
    printf 'on: [push, pull_request]\njobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo\n'
    printf '  apply:\n'
    [[ -n "$1" ]] && printf '    if: %s\n' "$1"
    printf '    runs-on: [self-hosted, acme-jump]\n    steps:\n'
    [[ -n "${2:-}" ]] && printf '      - if: %s\n        run: echo\n' "$2"
    printf '      - run: echo\n'
  } >"$TEST_TMP/wf.yml"
  run bash -c 'source "$REPO_ROOT/tracks/ansible/lib/ansible.sh" && an_wf_fork_guard apply "$1"' _ "$TEST_TMP/wf.yml"
}

@test "M7: fork guard accepts the guard AND-ed in, as the references write it" {
  fork_guard "github.event_name == 'pull_request' && $PRG"
  [ "$status" -eq 0 ]
  fork_guard "(github.event_name == 'push' || (github.event_name == 'workflow_dispatch' && inputs.task == 'apply')) && $PRG"
  [ "$status" -eq 0 ]
  fork_guard "\${{ $G }}"
  [ "$status" -eq 0 ]
  fork_guard "github.repository == github.event.pull_request.head.repo.full_name && github.event_name == 'pull_request'"
  [ "$status" -eq 0 ]
  fork_guard "github.event_name != 'pull_request' || $G"
  [ "$status" -eq 0 ]
  fork_guard "always() && $PRG"
  [ "$status" -eq 0 ]
}

@test "M7: fork guard rejects always() ||, an OR-ed or negated guard, and a guard on a step only" {
  fork_guard "always() || $G"
  [ "$status" -ne 0 ]
  fork_guard "$G || github.event_name == 'pull_request'"
  [ "$status" -ne 0 ]
  fork_guard "always() || $PRG"
  [ "$status" -ne 0 ]
  fork_guard "(github.event_name == 'pull_request' || $G) && inputs.env == 'dev'"
  [ "$status" -ne 0 ]
  fork_guard "github.event_name == 'push' || github.event_name == 'pull_request' && $PRG"
  [ "$status" -ne 0 ]
  fork_guard "!($G)"
  [ "$status" -ne 0 ]
  fork_guard "github.event.pull_request.head.repo.full_name == github.repository_owner"
  [ "$status" -ne 0 ]
  fork_guard "" "$G"
  [ "$status" -ne 0 ]
}

@test "M7: every reference workflow's runner jobs pass the fork guard" {
  local wf j n=0
  for wf in "$REPO_ROOT"/tracks/*/*/reference/live/.github/workflows/ansible.yml; do
    while IFS= read -r j; do
      [[ -n "$j" ]] || continue
      run bash -c 'source "$REPO_ROOT/tracks/ansible/lib/ansible.sh" && an_wf_fork_guard "$1" "$2"' _ "$j" "$wf"
      echo "$wf $j"
      [ "$status" -eq 0 ]
      n=$((n + 1))
    done < <(bash -c 'source "$REPO_ROOT/tracks/ansible/lib/ansible.sh" && an_wf_runner_jobs "$1"' _ "$wf")
  done
  [ "$n" -gt 0 ]
}

# --- M3: tf-05 tells the learner not to name the jobs ------------------------------------------

@test "M3: tf-05 says not to give the plan/apply jobs a name: (checks find them by id)" {
  grep -q 'name:' "$REPO_ROOT/tracks/terraform/05-pipeline/task.md"
  grep -qi "don't give the jobs a \`name:\`" "$REPO_ROOT/tracks/terraform/05-pipeline/hint.md"
}

# --- M4: site.yml's runner-key slurp fails unless the key file is simply missing ----------------

SITES="tracks/ansible/15-gh-runner/reference/live/ansible/site.yml
tracks/ansible/19-prod-guard/reference/live/ansible/site.yml
tracks/capstone/01-rebuild/reference/live/ansible/site.yml"

@test "M4: no reference site.yml ignores a failed runner-key read" {
  local f
  for f in $SITES; do
    ! grep -q 'failed_when: false' "$REPO_ROOT/$f"
    grep -q "'file not found' not in (acme_runner_pubkey.msg | default('') | lower)" "$REPO_ROOT/$f"
    grep -q 'ansible.builtin.assert' "$REPO_ROOT/$f"
  done
  ! grep -q 'failed_when: false' "$REPO_ROOT/tracks/ansible/15-gh-runner/solution.md"
  grep -q "'file not found'" "$REPO_ROOT/tracks/ansible/15-gh-runner/solution.md"
}

# m4_play <site.yml> <key path>: run that site.yml's runner-key pre_tasks on localhost (as the
# jump host), with acme_runner_pubkey_file = <key path>.
m4_play() {
  local py="${ANSIBLE_VENV:-$HOME/.local/share/platform-practice/venv}/bin/python3"
  "$py" - "$REPO_ROOT/$1" "$TEST_TMP/m4.yml" <<'PY'
import sys, yaml
site = yaml.safe_load(open(sys.argv[1]))
pre = next(p for p in site if isinstance(p, dict) and p.get('pre_tasks'))['pre_tasks']
yaml.safe_dump([{'hosts': 'all', 'gather_facts': False, 'pre_tasks': pre,
                 'tasks': [{'ansible.builtin.debug': {'msg': 'base would run'}}]}],
               open(sys.argv[2], 'w'), sort_keys=False)
PY
  printf '[role_jump]\nlocalhost ansible_connection=local ansible_python_interpreter=%s\n' "$py" >"$TEST_TMP/m4.ini"
  run "$(dirname "$py")/ansible-playbook" -i "$TEST_TMP/m4.ini" "$TEST_TMP/m4.yml" -e "acme_runner_pubkey_file=$2"
}

@test "M4: the runner-key pre_tasks pass on a missing key file and stop on any other read failure" {
  [[ -x "${ANSIBLE_VENV:-$HOME/.local/share/platform-practice/venv}/bin/ansible-playbook" ]] || skip "no ansible venv"
  local f
  echo "ssh-ed25519 AAAA runner" >"$TEST_TMP/key.pub"
  mkdir -p "$TEST_TMP/a-directory"
  for f in $SITES; do
    m4_play "$f" "$TEST_TMP/missing.pub"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"base would run"* ]]
    m4_play "$f" "$TEST_TMP/key.pub"
    [ "$status" -eq 0 ]
    m4_play "$f" "$TEST_TMP/a-directory"
    echo "$output"
    [ "$status" -ne 0 ]
    [[ "$output" != *"base would run"* ]]
  done
}
