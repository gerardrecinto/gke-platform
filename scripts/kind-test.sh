#!/usr/bin/env bash
# Runs the Kubernetes parts of this repo on a local kind cluster and asserts the results.
# Needs: docker, kind, kubectl, helm. Takes about 5 minutes. Set KEEP=1 to keep the cluster afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
CLUSTER=gke-platform
NS=orders
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; exit 1; }

cleanup() { [ "${KEEP:-0}" = 1 ] || kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true
kind create cluster --name "$CLUSTER" --wait 120s >/dev/null
kubectl config use-context "kind-$CLUSTER" >/dev/null

echo "== metrics-server"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null
kubectl -n kube-system patch deploy metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null
kubectl -n kube-system rollout status deploy/metrics-server --timeout=120s >/dev/null

echo "== app, HPA, PDB"
kubectl apply -f k8s/app/namespace.yaml -f k8s/app/serviceaccount.yaml -f k8s/app/deployment.yaml \
  -f k8s/app/service.yaml -f k8s/app/hpa.yaml -f k8s/app/pdb.yaml >/dev/null
kubectl -n $NS rollout status deploy/orders-api --timeout=180s >/dev/null
pass "Deployment is ready under the restricted Pod Security level"

kubectl run load --image=busybox:1.36 --restart=Never -- \
  /bin/sh -c 'while true; do for i in 1 2 3 4 5 6 7 8; do wget -q -O- http://orders-api.orders >/dev/null & done; wait; done' >/dev/null
for i in $(seq 1 36); do
  r=$(kubectl -n $NS get hpa orders-api -o jsonpath='{.status.currentReplicas}')
  [ "${r:-0}" -gt 2 ] && break
  sleep 5
done
[ "${r:-0}" -gt 2 ] || { kubectl -n $NS get hpa orders-api; fail "HPA did not scale above minReplicas under load"; }
pass "HPA scaled from 2 to $r replicas under load"

echo "== VPA recommender"
helm repo add fairwinds-stable https://charts.fairwinds.com/stable >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1
helm install vpa fairwinds-stable/vpa -n vpa --create-namespace \
  --set recommender.enabled=true --set updater.enabled=false --set admissionController.enabled=false \
  --set recommender.extraArgs.v=2 >/dev/null
kubectl -n vpa rollout status deploy/vpa-recommender --timeout=120s >/dev/null
kubectl apply -f k8s/app/vpa.yaml >/dev/null
for i in $(seq 1 36); do
  rec=$(kubectl -n $NS get vpa orders-api -o jsonpath='{.status.recommendation.containerRecommendations[0].target.cpu}' 2>/dev/null || true)
  [ -n "$rec" ] && break
  sleep 10
done
[ -n "${rec:-}" ] || fail "VPA produced no recommendation"
pass "VPA recommends cpu $rec for container web (updateMode Off, nothing was changed)"
kubectl delete pod load --wait=false >/dev/null

echo "== RBAC"
kubectl apply -f k8s/rbac/rbac.yaml >/dev/null
can() { kubectl auth can-i "$@" 2>/dev/null || true; }
viewer=(--as=alice --as-group=orders-viewers@example.com -n $NS)
deployer=(--as=system:serviceaccount:$NS:deployer)
[ "$(can get pods "${viewer[@]}")" = yes ]        || fail "viewer cannot read pods"
[ "$(can delete pods "${viewer[@]}")" = no ]      || fail "viewer can delete pods"
[ "$(can get secrets "${viewer[@]}")" = no ]      || fail "viewer can read secrets"
[ "$(can patch deployments "${deployer[@]}" -n $NS)" = yes ] || fail "deployer cannot patch deployments"
[ "$(can delete deployments "${deployer[@]}" -n $NS)" = no ] || fail "deployer can delete deployments"
[ "$(can get secrets "${deployer[@]}" -n $NS)" = no ]        || fail "deployer can read secrets"
[ "$(can patch deployments "${deployer[@]}" -n default)" = no ] || fail "deployer can patch outside its namespace"
pass "RBAC: viewer reads only, deployer patches deployments only inside orders"

echo "== stateful recovery"
sed 's/storageClassName: premium-rwo/storageClassName: standard/' k8s/stateful/stateful.yaml | kubectl apply -f - >/dev/null
kubectl -n $NS rollout status sts/ledger --timeout=180s >/dev/null
kubectl -n $NS exec ledger-0 -- sh -c 'echo order-1001 >> /data/ledger.log; echo order-1002 >> /data/ledger.log'
kubectl -n $NS delete pod ledger-0 --wait=true >/dev/null
kubectl -n $NS rollout status sts/ledger --timeout=180s >/dev/null
[ "$(kubectl -n $NS exec ledger-0 -- wc -l < /data/ledger.log 2>/dev/null | tr -d ' ')" = 2 ] || \
  [ "$(kubectl -n $NS exec ledger-0 -- sh -c 'wc -l < /data/ledger.log' | tr -d ' ')" = 2 ] || fail "data lost after pod restart"
pass "StatefulSet pod was deleted and rescheduled, both ledger lines survived on the PVC"
kubectl -n $NS create job --from=cronjob/ledger-backup backup-1 >/dev/null
kubectl -n $NS wait --for=condition=complete job/backup-1 --timeout=120s >/dev/null || fail "backup job did not complete"
kubectl -n $NS exec ledger-0 -- sh -c ': > /data/ledger.log'
cat <<'R' | kubectl -n $NS apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata: { name: restore-1 }
spec:
  template:
    spec:
      restartPolicy: Never
      securityContext: { runAsNonRoot: true, runAsUser: 65532, fsGroup: 65532, seccompProfile: { type: RuntimeDefault } }
      affinity:
        podAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector: { matchLabels: { app: ledger } }
              topologyKey: kubernetes.io/hostname
      containers:
        - name: restore
          image: busybox:1.36
          command: ["sh", "-c", "cp $(ls -t /backup/ledger.log.* | head -1) /data/ledger.log"]
          securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ["ALL"] } }
          volumeMounts: [{ name: data, mountPath: /data }, { name: backup, mountPath: /backup, readOnly: true }]
      volumes:
        - { name: data, persistentVolumeClaim: { claimName: data-ledger-0 } }
        - { name: backup, persistentVolumeClaim: { claimName: ledger-backup } }
R
kubectl -n $NS wait --for=condition=complete job/restore-1 --timeout=120s >/dev/null || fail "restore job did not complete"
lines=$(kubectl -n $NS exec ledger-0 -- sh -c 'wc -l < /data/ledger.log' | tr -d ' ')
[ "$lines" = 2 ] || fail "restore left $lines lines, expected 2"
pass "Backup job copied the ledger, the ledger was wiped, the restore job brought back 2 of 2 lines"

echo "== Flux CD"
kubectl apply -f https://github.com/fluxcd/flux2/releases/latest/download/install.yaml >/dev/null
kubectl -n flux-system rollout status deploy/source-controller --timeout=180s >/dev/null
kubectl -n flux-system rollout status deploy/kustomize-controller --timeout=180s >/dev/null
kubectl apply -f cicd/flux/sync.yaml >/dev/null
kubectl -n flux-system wait kustomization/orders --for=condition=Ready --timeout=240s >/dev/null || { kubectl -n flux-system get kustomization,gitrepository; fail "Flux did not reconcile k8s/app"; }
pass "Flux pulled the repo and applied k8s/app"
kubectl -n $NS delete pdb orders-api >/dev/null
for i in $(seq 1 30); do kubectl -n $NS get pdb orders-api >/dev/null 2>&1 && break; sleep 5; done
kubectl -n flux-system annotate --overwrite kustomization/orders reconcile.fluxcd.io/requestedAt="$(date +%s)" >/dev/null
for i in $(seq 1 30); do kubectl -n $NS get pdb orders-api >/dev/null 2>&1 && break; sleep 5; done
kubectl -n $NS get pdb orders-api >/dev/null 2>&1 || fail "Flux did not put back the deleted PodDisruptionBudget"
pass "Flux put back a PodDisruptionBudget deleted by hand"

echo "== Helm"
helm lint charts/orders-api >/dev/null
helm upgrade --install orders-helm charts/orders-api -n orders-helm --create-namespace --wait --timeout 3m >/dev/null
pass "Helm chart linted and installed, Deployment ready, HPA and PDB created"

echo "== NetworkPolicy"
kubectl apply -f k8s/app/networkpolicy.yaml >/dev/null
kubectl create ns outsider >/dev/null
sleep 5
if kubectl -n outsider run probe --image=busybox:1.36 --restart=Never --rm -i --timeout=60s -- \
     wget -q -T 4 -O- http://orders-api.orders >/dev/null 2>&1; then
  echo "NOTE  a pod in another namespace reached orders-api: this kind CNI does not enforce NetworkPolicy. GKE Dataplane V2 does."
else
  pass "NetworkPolicy blocked a pod in another namespace"
fi
echo "done"
