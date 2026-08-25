# Day 6 - CI/CD and ship it

Today wires GitHub Actions to do what you've been doing by hand all week:
`terraform apply` on infra changes, and build/push/`helm upgrade` on app
changes. Six parts, done in order - don't skip ahead, each depends on the
one before it.

## Part A - One git repo for the whole project

Everything you've built lives in separate folders under
`~/terraform-helm-week/`. Today they become one repo.

```bash
cd ~/terraform-helm-week
git init
git branch -M main
```

Download `.gitignore` from the file card and place it at the **repo root**
(`~/terraform-helm-week/.gitignore`, not inside any subfolder).

**Important fix to a Day 1 decision:** open `day1-bootstrap/.gitignore`
and delete the `backend.tf` line if it's there. Back on Day 1, keeping
`backend.tf` out of git seemed like reasonable caution - but it contains no
actual secrets (just a resource group name, storage account name, and
container name), and GitHub Actions' checkout won't have it at all unless
it's committed. Without it, `terraform init` in CI has no idea where your
remote state lives.

Check what's about to be committed before you commit it:
```bash
git add -A
git status
```
Skim the file list. You should NOT see any `.tfstate` file, `.terraform/`
directory, or `.tfvars` file in there - if you do, stop and fix
`.gitignore` before committing. You SHOULD see `backend.tf`,
`values-override.yaml`, and every `.tf`/`.yaml`/`.py` file across all four
day-folders. Worth noting explicitly: the actual database password was
never written into any of these files all week - it went straight from
Terraform's output into a Kubernetes Secret via `kubectl create secret`
and nowhere else. That design choice from Day 5 is exactly what makes this
whole repo safe to commit as-is.

```bash
git commit -m "Terraform + Helm week: infra, app, and chart"
```

Create the GitHub repo (via https://github.com/new, or `gh repo create` if
you have the GitHub CLI installed), then:

```bash
git remote add origin <your-repo-url>
git push -u origin main
```

## Part B - An Azure identity for GitHub Actions to use

This creates an Azure AD App Registration with no password at all - it
authenticates by GitHub proving, via a signed token, that a specific
workflow in your specific repo is running. Azure trusts that token instead
of a stored secret.

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

# Create the app registration and its service principal
APP_ID=$(az ad app create --display-name "tfhelm-github-actions" --query appId -o tsv)
az ad sp create --id "$APP_ID"

# Grant it Contributor on just your resource group - not the whole subscription
az role assignment create \
  --assignee "$APP_ID" \
  --role Contributor \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/tfhelm-rg"
```

Now tell Azure to trust GitHub's tokens, but only for pushes to `main` in
your exact repo:

```bash
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters '{
    "name": "github-actions-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<your-github-username>/<your-repo-name>:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

Replace `<your-github-username>/<your-repo-name>` with your actual repo
path (e.g. `shrestahegde/terraform-helm-week`). This exact-match subject is
the whole security model here - a workflow anywhere else, even a fork of
your repo, would present a token with a different subject and be rejected.

Print the three values you'll need next (safe to view in your terminal,
none of these are secret the way a password is - but treat them the same
way regardless, as GitHub Secrets, not committed anywhere):

```bash
echo "AZURE_CLIENT_ID: $APP_ID"
echo "AZURE_TENANT_ID: $TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
```

## Part C - Add them as GitHub secrets

In your repo on GitHub: **Settings -> Secrets and variables -> Actions ->
New repository secret**. Add all three:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

## Part D - The workflow files

Download `infra.yml` and `app.yml` into `.github/workflows/` at your repo
root (create that folder if `git init` didn't create it for you).

Open `app.yml` and update the `env:` block near the top with your actual
values (ACR name, login server, resource group, cluster name) - they're
currently placeholders matching an example setup, not secrets, just
identifiers specific to your resources.

## Part E - Push and watch

```bash
git add -A
git commit -m "Add CI/CD workflows"
git push
```

On GitHub, go to the **Actions** tab. Since this push touches
`.github/workflows/` but not `day1-bootstrap/**` or `day4-app/**`, neither
workflow will actually trigger yet - that's the path filter working
correctly, not a bug. To actually test each workflow, make a trivial
change and push it:

```bash
# Test the infra workflow
echo '  test = "ci"' # (don't actually run this - see below)
```

Better: add a harmless tag to `day1-bootstrap/main.tf` (e.g. add
`ci = "true"` inside the `tags = { ... }` block on the resource group),
commit, and push. Watch the **Actions** tab - you should see the
Terraform workflow run `init`, `plan`, and `apply`, and since nothing
material changed, apply should report something like "1 to change" for
that tag, cleanly.

Then make a trivial change in `day4-app/app.py` (a comment is enough),
commit, and push - watch the app workflow build, push a new image tagged
with the commit SHA, and run `helm upgrade`.

## Part F - Verify

```bash
kubectl get pods -w
```

New pods should roll out with the new image. Confirm the app's still
answering:

```bash
curl http://<your-nip.io-host>/healthz
curl http://<your-nip.io-host>/tasks
```

Your existing task should still be there - CI/CD deployed new code without
touching your data.

## Troubleshooting

- **`AADSTS70021: No matching federated identity record found`** - the
  `subject` in your federated credential doesn't exactly match
  `repo:<owner>/<repo>:ref:refs/heads/main`. Typos here (wrong case, wrong
  branch name, extra/missing colon) are the single most common OIDC setup
  mistake - copy the value from your actual GitHub repo URL rather than
  retyping it.
- **Terraform: "Backend initialization required"** - `backend.tf` didn't
  actually get committed. Check `git ls-files day1-bootstrap/backend.tf`
  returns something; if empty, you likely still have it gitignored
  somewhere.
- **`docker push` / `az acr login` fails with a permission error** - the
  federated identity's Contributor role assignment may not have finished
  propagating yet (can take a minute), or double check the role assignment
  actually landed: `az role assignment list --assignee $APP_ID -o table`.
- **Workflow doesn't trigger at all** - check the `paths:` filter matches
  what you actually changed, and that you pushed to `main` specifically
  (not another branch).

## You're done - what actually got built this week

- **Terraform**: resource group, remote state, ACR, an AKS cluster
  (modularized, with a managed identity for ACR access), a managed
  Postgres instance - all reproducible from code, all destroyable with
  `terraform destroy`
- **Helm**: a hand-written chart with real health probes, resource
  limits, a Kubernetes Secret wired in without ever touching a values
  file, and an Ingress routing real traffic through a correctly-probed
  Load Balancer
- **CI/CD**: two path-triggered GitHub Actions workflows, authenticating
  to Azure with no stored password anywhere, deploying on every push

And a real list of production-grade problems you actually debugged rather
than read about: three separate Azure provider breaking changes, a
subscription VM-quota restriction, a container permission bug, an image
path parsing bug, an Apple Silicon/amd64 architecture mismatch, an Azure
Load Balancer health-probe misconfiguration, and a regional capacity gap
for a managed database. That list is the real curriculum - the Terraform
and Helm syntax was just the material it happened to show up in.
