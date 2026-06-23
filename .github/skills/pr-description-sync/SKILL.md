---
name: pr-description-sync
description: >
  USE FOR: Any time you push one or more commits to a branch that already has
  an open pull request in the Voltpit (tesla-dash) repo. Enforces that the PR
  description is updated to reflect what the new commits changed BEFORE you
  consider the push complete. Triggers: "push to the PR", "push this fix",
  "git push" on a branch with an open PR, "update the branch", "amend the PR",
  "add a commit to the PR". DO NOT USE FOR: the very first push that opens the
  PR (the PR body is written then), read-only git operations, or pushes to a
  branch with no open PR.
---

# Keep the PR description in sync on every push

A pull request description is the reviewer's source of truth for what the PR
does. When you push new commits to a branch that already has an open PR, the
diff changes but the description goes stale unless you update it. Always refresh
the PR body so it matches the full, current state of the branch.

Copilot owns this: when you (the agent) push commits to a branch with an open
PR, you regenerate the PR description yourself and apply it. Do not leave it for
the user to update manually and do not just tell them to do it.

## Hard rule

Whenever you push to a branch that has an open PR, ALWAYS:

1. Push the commit(s).
2. Determine what changed since the PR body was last written (see below).
3. Regenerate the PR description and apply it with the PR tooling.
4. Only then report the push as done.

Do this even when the user does not explicitly ask, and even for small fixes.
The first push that opens the PR is exempt (the body is authored at that point).

## How to apply the update

Use whichever PR tool is available, in this order of preference:

1. The GitHub Pull Request tools exposed in this environment
   (`github-pull-request_*` / `mcp_github-mcp-se_update_pull_request`) when the
   PR is the active one in VS Code.
2. The `gh` CLI fallback below.

## Workflow

```bash
# 1. Confirm there is an open PR for the current branch and get its number.
gh pr view --json number,title,url,body --jq '{number,title,url}'

# 2. See what the new commits changed (since origin before the push, or since
#    the commit the current PR body described).
git --no-pager log origin/main..HEAD --oneline
git --no-pager diff --stat origin/main...HEAD

# 3. Update the PR body. Prefer editing the whole body so it stays coherent,
#    not just appending. Keep the existing structure (Summary, sections,
#    Testing, Docs) and revise the affected parts.
gh pr edit <number> --body "$(cat <<'EOF'
<full, updated PR description>
EOF
)"
```

## What to update in the description

- **Summary / scope**: if the push adds, removes, or changes a feature, reflect
  it in the summary so it describes the whole branch, not just the original.
- **Removed work**: if a commit drops something the body still advertises (e.g.
  a removed workflow or reverted change), delete or correct that claim.
- **Testing**: update the testing notes to match the latest commits (new tests
  run, fixes verified, items still pending).
- **Follow-ups / known gaps**: keep the "not yet done" list accurate.

## Reminders

- Edit the body to stay coherent as a whole; do not just bolt on a changelog of
  the latest commit.
- Follow the repo rule: run `ghswitch restlessankyyy` before any git/gh write,
  and commit with the personal email `rajankit749@gmail.com`.
- Never use the em dash character in the PR body or commit messages; use commas,
  colons, parentheses, or "to" instead.
- If the new commits also change architecture, the `pr-architecture-sync` skill
  still applies: update the architecture docs in the same push.
