# an-04 solution

## Approach

Configs next to the code in `ansible/`, the linters pinned twice in the same versions (venv for
running them by hand, hook revs for pre-commit), and the hooks pointed at `ansible/` because
pre-commit runs from the repo root. The an-03 reference role already passes the production profile;
your own role probably had a few `fqcn`, `name[casing]` or `var-naming` findings.

## Code

`ansible/.ansible-lint`:

```yaml
---
profile: production
exclude_paths:
  - .venv/
  - collections/ansible_collections/
  - .ansible/
```

`ansible/.yamllint`:

```yaml
---
extends: default
ignore: |
  .venv/
  collections/ansible_collections/
  .ansible/
rules:
  line-length:
    max: 160
  comments:
    min-spaces-from-content: 1
  comments-indentation: false
  braces:
    max-spaces-inside: 1
  octal-values:
    forbid-implicit-octal: true
    forbid-explicit-octal: true
  truthy:
    allowed-values: ["true", "false"]
    check-keys: false
```

`ansible/.pre-commit-config.yaml`:

```yaml
---
repos:
  - repo: https://github.com/adrienverge/yamllint
    rev: v1.38.0
    hooks:
      - id: yamllint
        files: ^ansible/
        args: [--strict, -c, ansible/.yamllint]

  - repo: https://github.com/ansible/ansible-lint
    rev: v26.11.0
    hooks:
      - id: ansible-lint
        files: ^ansible/
        language_version: python3.12
        additional_dependencies:
          - ansible-core==2.21.6
        entry: python3 -m ansiblelint --project-dir ansible -c ansible/.ansible-lint
```

Added to `ansible/requirements.txt`:

```text
ansible-lint==26.11.0
yamllint==1.38.0
pre-commit==4.7.0
```

## Commands

```bash
cd "$LIVE_DIR/ansible" && source .venv/bin/activate
pip install -r requirements.txt
ansible-lint                                   # fix every finding, re-run until it passes
cd "$LIVE_DIR"
pre-commit install --config ansible/.pre-commit-config.yaml
pre-commit run --config ansible/.pre-commit-config.yaml --all-files
# prove the gate: a free-form, non-FQCN task must be rejected
printf '\n- name: bad\n  shell: echo hi\n' >> ansible/roles/base/tasks/main.yml
git commit -am "should fail"                   # ansible-lint: fqcn, name[casing], no-changed-when, ...
git checkout -- ansible/roles/base/tasks/main.yml
git add ansible && git commit -m "ansible: lint gates" && git push   # on a branch, then a PR
```

`pre-commit autoupdate --config ansible/.pre-commit-config.yaml` bumps the revs later, as a reviewed
change; update `requirements.txt` in the same pull request.

## Verify

`./lab.sh grade`. The first `pre-commit run` builds the hook environments (a minute or two);
later runs take seconds.
