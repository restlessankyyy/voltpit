---
name: terraform-remote-state
description: >
  USE FOR: Any Terraform operation in the Voltpit (tesla-dash) repo:
  init, plan, apply, destroy, import, state, output, or refresh under infra/.
  Enforces that the Azure Storage azurerm backend (remote state) is the single
  source of truth and that you never trust, edit, or commit the local
  terraform.tfstate. Triggers: "terraform plan", "terraform apply",
  "terraform init", "deploy infra", "run deploy.sh", "import resource",
  "terraform state", "check what is deployed". DO NOT USE FOR: editing .tf
  source files without running Terraform, or non-Terraform tasks.
---

# Remote state is the source of truth

The Voltpit infra uses an `azurerm` backend in Azure Storage (configured in
[infra/backend.tf](../../../infra/backend.tf) with values from the gitignored
`infra/backend.hcl`). That remote blob is the ONLY authoritative record of what
is deployed. A local `infra/terraform.tfstate` file is never authoritative and
must not be trusted, hand-edited, or treated as current.

## Hard rules

1. **Always initialize against the remote backend before any state-reading or
   state-changing command.** Never run `plan`, `apply`, `destroy`, `import`,
   `state`, `output`, or `refresh` without first running:

   ```bash
   cd infra
   [ -f backend.hcl ] || ./bootstrap-state.sh   # creates the state storage + backend.hcl
   terraform init -backend-config=backend.hcl
   ```

   `infra/deploy.sh` already does this; prefer running it over ad-hoc commands.

2. **Never answer "what is deployed?" from the local `terraform.tfstate`.**
   Read it from the remote backend after `init`, e.g. `terraform state list`,
   `terraform show`, or `terraform output`. If asked whether something exists in
   Azure, verify against remote state (or `az`), not the local file.

3. **Never commit or hand-edit state.** Do not `git add` any
   `terraform.tfstate*` file, and do not edit state JSON directly. Use
   `terraform state mv/rm/import` against the remote backend instead. If a stale
   local `terraform.tfstate` exists in the working tree, ignore it as a source
   of truth and rely on the remote backend after `init`.

4. **Never run `-backend=false` or skip `init` to "save time".** That detaches
   you from the source of truth and risks a divergent plan.

5. **One writer at a time.** The azurerm backend takes a blob lease lock. Do not
   bypass locks (`-lock=false`) except for a read-only `plan` when you have
   confirmed no apply is in flight, and never for `apply`.

## Authentication

The backend uses `use_azuread_auth = true`, so it authenticates with the
signed-in Azure CLI user. Run `az login` first. `bootstrap-state.sh` grants that
user `Storage Blob Data Contributor` on the state account. No storage keys, no
service principal, no secrets in the repo.

## Reminders

- This is local-only deployment driven by `az` CLI auth; there is no GitHub
  CI/CD for Terraform. The remote state lives in Azure Storage, not in git.
- Follow `ghswitch-account` rules for any git write, and never use the em dash
  character in output or commits.
