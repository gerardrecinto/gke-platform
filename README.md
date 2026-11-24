# gke-platform

[![CI](https://github.com/gerardrecinto/gke-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/gerardrecinto/gke-platform/actions/workflows/ci.yml)

GKE Standard and Autopilot as code: Terraform, Workload Identity, autoscaling, RBAC, stateful recovery, ingress and CI/CD, with the Kubernetes parts run on a kind cluster in CI.

**Site and planner: https://gerardrecinto.github.io/gke-platform/**

Lab scale. Nothing here has been applied to a live Google Cloud project (see "What is verified").

## What is in it

| Folder | What | Check |
|---|---|---|
| `terraform/modules/network` | Custom VPC, secondary ranges for pods and services, Cloud NAT, health check firewall | validate, trivy |
| `terraform/modules/gke-standard` | Private regional cluster, Dataplane V2, Workload Identity, VPA, release channel, node pool with Cluster Autoscaler bounds, surge upgrades, shielded nodes, Managed Prometheus | validate, trivy |
| `terraform/modules/gke-autopilot` | Autopilot cluster on the same network | validate, trivy |
| `terraform/modules/workload-identity` | Google service account bound to one Kubernetes service account | validate, annotation test |
| `terraform/modules/observability`, `backup` | PromQL alerts, log metric, Backup for GKE plan | validate |
| `k8s/app` | Deployment (restricted Pod Security), Service with NEG, HPA, VPA (Off), PDB, NetworkPolicy | kind |
| `k8s/rbac` | Read-only viewers, narrow deployer | kind, seven `can-i` assertions |
| `k8s/stateful` | StatefulSet, backup CronJob, restore | kind, wipe and restore |
| `k8s/ingress` | Ingress, BackendConfig, FrontendConfig, ManagedCertificate, Gateway API | cross-reference tests |
| `cicd/` | Cloud Build, Argo CD Application, GitHub OIDC deploy template | shape tests |
| `src/gkeplan`, `site/` | Allocatable, HPA, VPA and node-count maths, and the Pages planner | 30 pytest tests, JS parity on 90 cases |

## Run it

```bash
git clone https://github.com/gerardrecinto/gke-platform && cd gke-platform
./scripts/kind-test.sh        # needs docker, kind, kubectl, helm; about 5 minutes
python3 -m venv .venv && . .venv/bin/activate && pip install -e ".[dev]" && pytest -q
python -m gkeplan nodes --replicas 40 --cpu 500 --mem 512
cd terraform/envs/dev && terraform init -backend=false && terraform validate
```

If Docker is not running, `kind-test.sh` stops at cluster creation; start Docker first. Operations steps are in [docs/RUNBOOK.md](docs/RUNBOOK.md).

## Design choices

- **Standard and Autopilot both.** Autopilot for ordinary services where requests are the only knob; Standard when a workload needs host access or bin packing is the cost lever. Cost of Autopilot: less node detail. Flip when an agent needs the host.
- **HPA on CPU, VPA in recommendation mode.** Both on CPU with the VPA on Auto would chase each other, and a test fails the build if that happens. Cost: requests are changed by a person.
- **Private nodes, public control plane endpoint with authorized networks.** Cheaper and simpler than a fully private endpoint plus a bastion. Flip to a private endpoint when the CI runners sit inside the VPC.
- **Node pool managed apart from the cluster** (`remove_default_node_pool`), so a pool change never recreates the cluster.
- **Argo CD for deploy, Cloud Build for build.** Cloud Build never holds cluster credentials. Cost: one more system to run.
- **Gateway API next to Ingress.** Ingress is what most clusters run today; Gateway is where GKE is going.

## What is verified

- **Run on kind, asserted by `scripts/kind-test.sh` and CI:** the Deployment starts under the restricted Pod Security level, the HPA scales past 2 replicas under load, the VPA recommender produces a CPU recommendation, RBAC allows and denies as written, a NetworkPolicy blocks a pod from another namespace, a StatefulSet pod survives deletion, and a wiped ledger is restored from the backup volume.
- **Checked without a cloud:** `terraform fmt`, `validate`, a trivy config scan with no high or critical findings, manifest cross-reference tests, Python tests, and a JavaScript port checked against Python.
- **Not run:** `terraform apply` or plan against a Google project, Workload Identity token exchange, the Google load balancer and managed certificate, Managed Prometheus alerts, Backup for GKE, Cloud Build, Argo CD, and the Cluster Autoscaler itself (it is a node pool setting; the planner models it). The allocatable figures follow the GKE reservation tiers and match the documented 3920m for a 4 vCPU node; memory was not compared against a live node.

MIT licensed.
