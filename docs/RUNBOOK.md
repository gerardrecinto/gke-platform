# Runbook

## HPA is pinned at max and latency is rising
1. `kubectl -n orders get hpa orders-api`: is TARGETS above 50% with REPLICAS equal to MAXPODS? The "HPA pinned at max" alert fires on this.
2. `kubectl -n orders get pods | grep Pending`: pending pods mean the node pool is at its Cluster Autoscaler maximum. Raise `max_nodes_per_zone` in `terraform/envs/dev/main.tf` (the value is per zone).
3. If pods are Running and CPU is still high, raise `maxReplicas`, or raise requests using the VPA recommendation: `kubectl -n orders get vpa orders-api -o jsonpath='{.status.recommendation}'`.

## A StatefulSet pod will not start after a node was replaced
A ReadWriteOnce disk lives in one zone. If the pod is Pending with a volume node affinity conflict, the zone has no capacity. Check `kubectl describe pod`, then add capacity in that zone, or restore from Backup for GKE into another zone.

## Restore the ledger from the file-level backup
`kubectl -n orders create job --from=cronjob/ledger-backup backup-now` takes a copy. The restore job in `scripts/kind-test.sh` shows the reverse copy from the newest file on the `ledger-backup` volume.

## Backup for GKE
Terraform enables the agent and defines a daily plan (`terraform/modules/backup`). The plan has not been applied to a live project.

## Workload Identity: pod gets a 403 from a Google API
1. The Kubernetes ServiceAccount annotation must equal the Google service account email (`terraform output orders_google_sa`).
2. The binding member must read `PROJECT.svc.id.goog[orders/orders-api]`.
3. The Google service account needs the role for the API it calls. Check the `roles` list in `modules/workload-identity`.
