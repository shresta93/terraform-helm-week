# Day 4 - Dockerize your app + write your own Helm chart

Today has two halves: get the task API into a container and into your ACR,
then write (not just consume, like Day 3) a Helm chart for it and deploy
to your AKS cluster.

## 0. The app

A small Flask task-tracking API: `GET/POST /tasks`, `PATCH /tasks/<id>`,
`DELETE /tasks/<id>`, plus `/healthz`. It needs a `DATABASE_URL` env var to
actually do anything with `/tasks` - which doesn't exist until Day 5. This
is intentional, not a gap: `/healthz` deliberately never touches the
database, so the pod can be genuinely healthy and pass Kubernetes' probes
even before Postgres exists. Hitting `/tasks` today will correctly return
a `503` - that's the app telling you the truth, not a bug.

## 1. Build and test the image locally

```bash
cd day4-app
docker build -t task-api:local .
docker run --rm -p 8080:8080 task-api:local
```

In another terminal:
```bash
curl localhost:8080/healthz     # {"status": "ok"}
curl localhost:8080/tasks       # 503, database unavailable - expected today
```

Ctrl-C the running container once you've confirmed both.

## 2. Push it to your ACR

Get your registry name from Day 1's Terraform outputs:
```bash
cd ../day1-bootstrap
terraform output acr_login_server
cd ../day4-app
```

Then:
```bash
az acr login --name <acr-name-without-.azurecr.io>
docker build -t <acr_login_server>/task-api:v1 .
docker push <acr_login_server>/task-api:v1
```

`az acr login` uses your existing `az login` session - no separate
username/password to manage, same "no stored credentials" pattern as the
managed identity from Day 2.

## 3. The Helm chart

`taskapi-chart/` is hand-written rather than starting from `helm create`,
so every line in it is something you should be able to explain - there's
no scaffold boilerplate to wade through. It's intentionally minimal:

- **`Chart.yaml`** - metadata (name, version)
- **`values.yaml`** - defaults: image, replica count, resource
  requests/limits, probe config, and a `databaseSecretName` hook that's
  empty today and gets filled in on Day 5
- **`templates/deployment.yaml`** - the Deployment: note the
  `{{- if .Values.databaseSecretName }}` block - Go templating's
  conditional syntax. Since the value is empty today, that whole block
  renders to nothing; no `DATABASE_URL` env var gets injected until Day 5
  sets it
- **`templates/service.yaml`** - a `ClusterIP` Service, not
  `LoadBalancer`. You already have a working Load Balancer + public IP
  from ingress-nginx (Day 3) - Day 5 routes through that via an Ingress
  resource instead of paying for and managing a second one

Worth actually reading both template files before deploying - you should
be able to point at any line and say what Kubernetes object or field it
produces.

## 4. Point the chart at your image

Open `values-override.yaml` and replace the placeholder with your real
ACR login server:

```yaml
image:
  repository: "<your-acr-login-server>/task-api"
  tag: "v1"
```

## 5. Render before installing (same habit as Day 3)

```bash
helm template taskapi ./taskapi-chart -f values-override.yaml | less
```

Confirm the image line, replica count, and probe paths look right in the
rendered output before it touches your cluster.

## 6. Install

```bash
helm install taskapi ./taskapi-chart -f values-override.yaml
```

## 7. Verify

```bash
kubectl get pods
kubectl get deploy taskapi-taskapi
kubectl logs deploy/taskapi-taskapi
```

Both pods should reach `Running` / `1/1 Ready` fairly quickly - if either
is `ImagePullBackOff`, double check the `image.repository` value and that
`docker push` in step 2 actually succeeded (`az acr repository list
--name <acr-name> -o table` should list `task-api`).

Port-forward and hit it directly, bypassing ingress entirely for now:

```bash
kubectl port-forward svc/taskapi-taskapi 8080:80
```

In another terminal:
```bash
curl localhost:8080/healthz     # {"status": "ok"}
curl localhost:8080/tasks       # still 503 - correct, no DB yet
```

Ctrl-C the port-forward when done.

## Troubleshooting

- **`ImagePullBackOff` / `ErrImagePull`** - almost always a wrong
  `image.repository` value, or the AKS-to-ACR role assignment from Day 2
  not having propagated yet (rare, but can take a minute after `apply`).
  `kubectl describe pod <pod-name>` shows the exact pull error in Events.
- **Pod stuck `Pending`** - `kubectl describe pod <pod-name>` and check
  Events for scheduling failures - usually means the single node doesn't
  have enough free CPU/memory for the requested resources. Check
  `kubectl top node` (needs metrics-server, on by default in AKS) or
  `kubectl describe node` for allocatable vs. requested.
- **`CrashLoopBackOff`** - `kubectl logs <pod-name> --previous` to see why
  the last attempt died. Since `/healthz` doesn't touch the database, a
  missing `DATABASE_URL` should NOT cause this today - if it does, that's
  worth debugging together rather than working around.

## Concepts to be able to explain before Day 5

- Why `/healthz` deliberately doesn't check the database, and what would
  go wrong if it did (hint: think back to Day 3's Azure LB probe bug -
  same category of mistake, different layer)
- What `{{ .Release.Name }}` resolves to, and why the Deployment and
  Service names both use it instead of a hardcoded name
- Why the Service is `ClusterIP` here instead of `LoadBalancer`
- The difference between a resource **request** and a **limit** in the
  `resources` block, and what happens in each case if a pod exceeds one
