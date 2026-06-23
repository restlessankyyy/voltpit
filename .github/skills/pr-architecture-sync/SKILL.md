---
name: pr-architecture-sync
description: >
  USE FOR: Any time you are about to create or open a pull request in the
  Voltpit (tesla-dash) repo. Enforces that docs/ARCHITECTURE.md (and the
  architecture sections in README.md / backend/README.md / the voltpit-dev
  skill) are reviewed and updated to reflect the change BEFORE the PR is
  created. Triggers: "create a PR", "open a pull request", "raise a PR",
  "gh pr create", "submit for review". DO NOT USE FOR: read-only git
  operations or commits that do not open a PR.
---

# Keep the architecture in sync before every PR

Voltpit's architecture is documented in Mermaid diagrams and component tables.
These docs are the source of truth for how the system fits together, so they
MUST be updated in the same PR as any change that affects structure, data flow,
or components. Never open a PR that changes architecture while leaving the docs
stale.

## Hard rule

Before running `gh pr create` (or otherwise opening a PR), ALWAYS:

1. Review the diff for architectural impact (see checklist below).
2. If there is any impact, update the architecture docs in the SAME branch/PR.
3. Only then create the PR.

Do this even when the user does not explicitly ask, and even for small changes.

## Architecture docs to keep in sync

| File | What it holds |
| --- | --- |
| `docs/ARCHITECTURE.md` | Primary source of truth: system overview + realtime data-flow Mermaid diagrams, component responsibilities. |
| `README.md` | Top-level Mermaid overview and the docs index table. |
| `backend/README.md` | Backend-specific architecture diagram. |
| `.github/skills/voltpit-dev/SKILL.md` | The ASCII architecture sketch and the path/responsibility table. |

## What counts as architectural impact

Update the docs when a change does any of the following:

- Adds, removes, or renames a component or module (e.g. a new
  `VehicleSource`, a telemetry receiver, a persistence store, a new route).
- Changes how data flows between components (new WebSocket path, a new ingest
  endpoint, polling to push, a new external dependency such as Cosmos DB).
- Adds or removes an Azure resource or changes the deployment topology in
  `infra/` (Container App, ACR, Cosmos, storage account, remote state).
- Changes the message contract (`VehicleState` / `ServerMessage`) or the
  `SOURCE` selection logic.
- Adds a new external integration (Tesla Fleet Telemetry, a new API).

Pure refactors, formatting, dependency bumps, and bug fixes that do not move any
of the above usually need no diagram change, but still skim the docs to confirm.

## Workflow

```bash
# 1. See what changed in the branch
git diff --stat main...HEAD

# 2. Inspect for architectural impact, then edit the docs as needed:
#    docs/ARCHITECTURE.md (update the Mermaid diagrams + component table),
#    plus README.md / backend/README.md / voltpit-dev SKILL.md if affected.

# 3. Commit the doc updates on the same branch (use ghswitch first per repo rules)
git add docs/ARCHITECTURE.md README.md backend/README.md .github/skills/voltpit-dev/SKILL.md
git commit -m "docs: update architecture for <change>"

# 4. Now open the PR
gh pr create --fill
```

## Reminders

- Keep Mermaid diagrams valid: render or sanity-check the fenced ```mermaid
  blocks before committing.
- Follow the repo rule: run `ghswitch restlessankyyy` before any git/gh write.
- Never use the em dash character in docs or commit messages; use commas,
  colons, parentheses, or "to" instead.
- If the change has genuinely no architectural impact, note that briefly in the
  PR description rather than skipping the review step.
