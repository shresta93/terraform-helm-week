# Day 5 - Managed Postgres + Ingress

Today's payoff: a real database, a real URL, and your app answering both
at once. Two separate additions, done in order.

## Part A - Provision Postgres with Terraform

This continues in `day1-bootstrap/` - same state as Days 1 and 2, same
pattern as adding the AKS module.

### 1. Add the module folder

```bash
cd ~/terraform-helm-week/day1-bootstrap
mkdir -p modules/postgres
```

Download `main.tf`, `variables.tf`, `outputs.tf` from the file cards and
move them into `modules/postgres/`.

### 2. Wire it into your root config

Add to your root `main.tf`:

```hcl
module "postgres" {
  source              = "./modules/postgres"
  prefix              = var.prefix
  suffix              = random_string.suffix.result
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}
```

Add to your root `outputs.tf`:

```hcl
output "postgres_fqdn" {
  value = module.postgres.fqdn
}

output "postgres_admin_username" {
  value = module.postgres.admin_username
}

output "postgres_admin_password" {
  value     = module.postgres.admin_password
  sensitive = true
}

output "postgres_database_name" {
  value = module.postgres.database_name
}
```

### 3. Apply

```bash
terraform init
terraform plan    # 4 resources to add: the server, its firewall rule,
                    # the database, and the random password
terraform apply
```

This is slower than AKS was fast, but slower than a normal resource -
expect a few minutes.

### Design choices, know these:

- **`public_network_access_enabled = true` + an "allow Azure services"
  firewall rule (`0.0.0.0`-`0.0.0.0`)** - this is a real simplification,
  not an oversight. It lets any Azure-internal traffic (including your AKS
  node) reach the server without you having to look up and pin AKS's exact
  outbound IP. A production setup would use a private endpoint instead -
  worth knowing you're trading isolation for simplicity here.
- **Password restricted to `-_.~` as special characters** - this password
  gets embedded directly into a connection URL in Part B. Characters like
  `@ : / ?` are URL syntax characters; if the random password contained
  one unescaped, it would break the URL's own structure instead of being
  read as part of the password.
- **`B_Standard_B1ms`, Burstable** - cheapest real tier (~$12-15/month
  compute + ~$4/month storage). Postgres Flexible Server also supports
  stop/start like AKS did:
  ```bash
  az postgres flexible-server stop --resource-group tfhelm-rg --name <server-name>
  ```
  (storage still bills while stopped, compute doesn't).

## Part B - Wire the database into your app

**Important: from this point on, do not paste the output of any command
that shows your database password into this chat.** Terraform outputs it
as `sensitive`, meaning it won't print on a bare `terraform output`, but
`terraform output -raw postgres_admin_password` will show the real value -
that's necessary for the commands below, but keep that specific output on
your terminal only.

### 1. Build the secret directly from Terraform's outputs

```bash
cd ~/terraform-helm-week/day1-bootstrap

DB_HOST=$(terraform output -raw postgres_fqdn)
DB_USER=$(terraform output -raw postgres_admin_username)
DB_PASSWORD=$(terraform output -raw postgres_admin_password)
DB_NAME=$(terraform output -raw postgres_database_name)

kubectl create secret generic taskapi-db \
  --from-literal=database-url="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:5432/${DB_NAME}?sslmode=require"
```

This is deliberately imperative (`kubectl create`, not a Helm template or
a values file) - the password never touches a `.yaml` file that could end
up committed to git. `sslmode=require` is needed because Azure Flexible
Server enforces TLS by default.

Confirm it exists (this only shows metadata, not the secret value):
```bash
kubectl get secret taskapi-db
```

### 2. Get your ingress controller's URL

You already have a real IP from Day 3. Turn it into a free DNS name using
nip.io's wildcard trick (any `a-b-c-d.nip.io` resolves straight to
`a.b.c.d` - no DNS registration needed):

```bash
INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "${INGRESS_IP//./-}.nip.io"
```

### 3. Update your chart's values

Add to `day4-app/taskapi-chart/templates/ingress.yaml` - already provided,
just download it into `taskapi-chart/templates/` alongside `deployment.yaml`
and `service.yaml`.

Edit `day4-app/values-override.yaml`, adding two things to what's already
there from Day 4:

```yaml
databaseSecretName: taskapi-db

ingress:
  enabled: true
  host: "<paste the nip.io hostname from step 2>"
```

### 4. Upgrade

```bash
cd ~/terraform-helm-week/day4-app
helm upgrade taskapi ./taskapi-chart -f values-override.yaml
kubectl get pods -w
```

Unlike Day 4's image-tag fix, this change doesn't need a manual
`kubectl rollout restart` - adding `databaseSecretName` and `ingress`
values changes the rendered pod spec itself (a new env var appears), which
gives the Deployment a new pod template hash and triggers a rolling update
automatically. Ctrl-C once both pods show `1/1 Running`.

### 5. The actual test

```bash
curl http://<your-nip.io-host>/healthz

curl -X POST http://<your-nip.io-host>/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Finish Terraform + Helm week"}'

curl http://<your-nip.io-host>/tasks
```

The last command should show the task you just created, coming back
through: your browser/terminal -> nip.io DNS -> Azure Load Balancer ->
ingress-nginx -> Ingress rule -> Service -> Pod -> Postgres -> back out
the same path. That whole chain, built one piece at a time this week, is
now a real thing you can hit from anywhere.

## Troubleshooting

- **`/tasks` still 503** - `kubectl logs deploy/taskapi-taskapi` for the
  real error. Common causes: the secret key name doesn't match (`app.py`
  reads `DATABASE_URL`, the chart maps it from a secret key literally
  named `database-url` - check both if you edited either).
- **`curl` to the nip.io host times out** - re-run the Day 3 troubleshooting
  sequence (NSG, LB probe) if the IP has changed since then, or confirm
  `kubectl get ingress` shows your host and an address.
- **Ingress shows no `ADDRESS`** - can take a minute after `helm upgrade`
  for ingress-nginx to notice the new Ingress object; give it a moment
  before assuming something's wrong.

## Concepts to be able to explain before Day 6

- Why the database secret was created with `kubectl create secret`
  directly, instead of through a `values.yaml` file or a Helm template
- What the "allow Azure services" firewall rule actually permits, and why
  that's a simplification you're deliberately choosing, not a default you
  didn't think about
- Why changing `values-override.yaml` triggered an automatic rolling
  update in Part B step 4, when Day 4's tag reuse didn't
- The full request path from `curl` to Postgres and back, in order
