# Day 3 - Helm fundamentals

Today you're not writing Terraform. You're learning Helm by installing a
real, widely-used public chart (ingress-nginx) onto the cluster you built
on Day 2 - and you'll keep this specific install for the rest of the week,
since Day 5 needs an ingress controller to expose your app.

This work happens in a **separate folder**, `day3-helm/`, sitting next to
(not inside) `day1-bootstrap/`. Helm and Terraform are two different tools
managing two different things here - Terraform owns the AKS cluster itself,
Helm owns what's running inside it. Keeping them in separate folders keeps
that mental model honest.

## 0. Confirm your cluster is live

```bash
kubectl get nodes
```

If this errors or comes back empty, go back to `day1-bootstrap/` and run
`terraform apply` first.

## 1. Install Helm

```bash
brew install helm
helm version
```

## 2. Chart anatomy (read before you install anything)

Every Helm chart is a folder with a predictable shape:

- **`Chart.yaml`** - metadata: name, version, description
- **`values.yaml`** - the default configuration. This is what you override.
- **`templates/`** - Kubernetes manifest templates (YAML with Go template
  syntax) that get rendered using values.yaml, producing the actual
  Deployments/Services/etc. that get applied to your cluster
- **`templates/_helpers.tpl`** - reusable template snippets/functions
- **`charts/`** - subcharts (dependencies), if any

You're not writing one of these yet - that's Day 4. Today you're a
*consumer* of someone else's chart, which is the more common Helm workflow
day-to-day anyway.

## 3. Add the ingress-nginx repo

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

A "repo" here is just an index of charts, similar conceptually to a
package registry (npm, PyPI) - `helm repo add` doesn't install anything,
it just tells your local Helm CLI where to look.

## 4. Inspect before you install - never trust a chart blindly

```bash
helm show chart ingress-nginx/ingress-nginx     # metadata
helm show values ingress-nginx/ingress-nginx | less   # every configurable option and its default
```

This matters more than it sounds like it does. A chart's `values.yaml` is
effectively a config surface someone else designed - skimming it before
you install is the Helm equivalent of reading a script before running
`curl | sh`.

## 5. Dry-run first

```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f ingress-nginx-values.yaml \
  --dry-run
```

This renders the final manifests (chart defaults + your `-f` overrides
merged together) and prints them without touching your cluster. Skim the
output - this is the actual Kubernetes YAML that's about to get applied.
Precedence, low to high: chart's own `values.yaml` defaults → your `-f`
file → any `--set` flags on the command line.

## 6. Actually install it

Drop `--dry-run` and run it for real:

```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  -f ingress-nginx-values.yaml
```

## 7. Verify

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx -w
```

Wait for the `EXTERNAL-IP` column on the `ingress-nginx-controller` service
to change from `<pending>` to a real IP - usually 1-2 minutes. Ctrl-C once
it shows an IP.

```bash
curl http://<that-external-ip>
```

A `404 Not Found` from nginx is the *correct* result here - it means the
controller is up and answering, it just doesn't have any ingress rules
pointing anywhere yet (that comes in Day 5, once your app exists).

## 8. Cost note - new line item

A `type: LoadBalancer` Service provisions a real Azure Standard Load
Balancer (~$0.025/hr) plus a Standard Public IP (~$0.005/hr) - together
roughly $0.03/hr, ~$22/month if left running continuously. Cheap relative
to the AKS node, but it's new and worth knowing about. Since Day 5 reuses
this exact ingress controller, I'd leave it running for the rest of the
week rather than reinstalling it later. If you want to pause it overnight
along with stopping the cluster, `az aks stop` (from Day 2) suspends
billing for the LB along with everything else on the node.

## 9. Helm's release management - the actual point of today

```bash
helm list -n ingress-nginx                       # what's installed
helm status ingress-nginx -n ingress-nginx        # current state of this release
helm get values ingress-nginx -n ingress-nginx    # what values are actually in effect right now
```

Now make a trivial change and upgrade, to see how that works:

```bash
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  -f ingress-nginx-values.yaml \
  --set controller.replicaCount=1

helm history ingress-nginx -n ingress-nginx       # you now have 2 revisions
```

And roll it back, to see that Helm keeps every revision as a real,
restorable thing:

```bash
helm rollback ingress-nginx 1 -n ingress-nginx
helm history ingress-nginx -n ingress-nginx       # now 3 revisions - rollback is itself a new revision, not a rewind
```

That last point is the thing to really internalize: **`helm upgrade` and
`helm rollback` don't mutate a release in place - each one creates a new,
numbered revision.** Nothing is ever silently overwritten; you can always
see the history and go back to any point in it.

## Concepts to be able to explain before Day 4

- The difference between a **chart** (the packaged template), a **release**
  (one installed instance of a chart, with a name), and a **repo** (where
  charts come from)
- What `-f values.yaml` actually does at install/upgrade time, and the
  precedence order when you combine it with `--set`
- Why `helm upgrade` creates a new revision instead of editing the existing
  one - and why that's what makes `helm rollback` possible at all
- Why a `404` from the ingress controller right now is a *good* sign, not
  a failure
