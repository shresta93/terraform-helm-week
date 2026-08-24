# Day 1 - Bootstrap (resource group, remote state, container registry)

## 0. Install tools (skip anything you already have)

- Terraform: https://developer.hashicorp.com/terraform/install
- Azure CLI: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
- kubectl: https://kubernetes.io/docs/tasks/tools/
- Helm: https://helm.sh/docs/intro/install/
- Docker: https://docs.docker.com/get-docker/

Verify:
```bash
terraform -version
az --version
kubectl version --client
helm version
docker --version
```

## 1. Log into Azure

```bash
az login
az account list --output table   # if you have multiple subscriptions
az account set --subscription "<subscription-id>"
```

If this is a brand new account, activate the free trial (12 months of free
services + $200 credit for 30 days) or check for student credits - either
covers this whole project many times over.




## 2. First apply (local state)

```bash
cd day1-bootstrap
terraform init
terraform plan      # read this output - understand every resource before applying
terraform apply
```

Type `yes` when prompted. This creates:
- A resource group
- A storage account + container to hold Terraform's remote state
- An Azure Container Registry (Basic tier, ~$0.17/day) for your app images later

## 3. Migrate to remote state

Copy the output values Terraform just printed, then:

1. Open `backend.tf.example`
2. Fill in the three values from your outputs
3. Rename it to `backend.tf`
4. Run:
   ```bash
   terraform init -migrate-state
   ```
   Say yes when it asks to copy existing state into Azure.

Why this matters: local `.tfstate` files aren't safe for anything beyond a
single-person, single-laptop experiment - they get lost, conflict, and
contain secrets in plaintext. Remote state is how real teams work, and
you'll want this in place before Day 2 provisions AKS (a much more
expensive-to-lose resource).

## 4. Sanity check

```bash
terraform state list
az group show --name $(terraform output -raw resource_group_name)
```

You should see your resource group, storage account, container, and ACR
in the state list, and `az group show` should return real JSON.

## Concepts to make sure you actually understand before Day 2

Don't just run the commands - be able to explain these out loud:
- What `terraform init` / `plan` / `apply` / `destroy` each do
- What the `.tfstate` file is and why Terraform needs it
- What a provider is, and how `required_providers` pins a version
- The difference between a resource and a data source
- Why we needed a two-step bootstrap (local state -> remote state) instead
  of just starting with a remote backend

## Cost check-in

Right now you're paying for: one Basic Container Registry (~$0.17/day) and
a storage account (a few cents/month). Nothing expensive yet - that starts
tomorrow with AKS nodes. If you want to stop for the day, no cleanup is
needed, this is all cheap enough to leave running.
