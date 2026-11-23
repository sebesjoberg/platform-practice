---
id: an-04
title: Lint gates
target_minutes: 15
requires: [tf-25, an-03]
---
# an-04 Lint gates

Two more people start writing roles next week. Before that, the team wants the house rules
enforced by a machine, not in review comments: the strictest ansible-lint profile, yamllint, and
both running on every commit. The same versions run locally, in the hooks and (from an-16) in CI.

## Deliverables

- [ ] `ansible/.ansible-lint` selects `profile: production`.
- [ ] `ansible/.yamllint`: yamllint's defaults plus the settings ansible-lint requires of a
      custom yamllint config (it refuses an incompatible one).
- [ ] `ansible/.pre-commit-config.yaml` with the hooks `yamllint`
      (`https://github.com/adrienverge/yamllint`) and `ansible-lint`
      (`https://github.com/ansible/ansible-lint`), each repo pinned with `rev:` to a **release
      tag**, never a branch. The config lives in `ansible/` with the rest of the track; the hooks
      run from the repo root and must lint only `ansible/`.
- [ ] `ansible/requirements.txt` also pins `ansible-lint`, `yamllint` and `pre-commit` (same
      versions as the hooks); the venv has them.
- [ ] `ansible-lint` passes on all of `ansible/` with zero findings. Fix what it finds in your
      an-01…an-03 code; a `# noqa` is allowed only with a reason next to it.
- [ ] The git hook is installed, so the hooks run on every commit.

## Done when

`ansible-lint` (from `ansible/`, venv active) ends with `Profile 'production' was required, and it
passed`, `pre-commit run --config ansible/.pre-commit-config.yaml --all-files` passes from the
repo root, a commit with a deliberately broken task is rejected, and `./lab.sh grade` passes.

Target: 15 minutes.
