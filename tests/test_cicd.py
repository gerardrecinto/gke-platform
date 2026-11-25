import pathlib

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent


def test_cloudbuild_steps_run_in_the_documented_order():
    cb = yaml.safe_load(open(ROOT / "cicd/cloudbuild.yaml"))
    ids = [s["id"] for s in cb["steps"]]
    assert ids == ["test", "build", "push", "scan", "update-manifest"]


def test_argocd_application_points_at_k8s_app_and_self_heals():
    app = yaml.safe_load(open(ROOT / "cicd/argocd/application.yaml"))
    assert app["spec"]["source"]["path"] == "k8s/app"
    assert app["spec"]["syncPolicy"]["automated"] == {"prune": True, "selfHeal": True}


def test_github_workflow_uses_oidc_not_keys():
    wf = yaml.safe_load(open(ROOT / ".github/workflows/deploy.yml"))
    job = next(iter(wf["jobs"].values()))
    assert wf["permissions"]["id-token"] == "write"
    text = open(ROOT / ".github/workflows/deploy.yml").read()
    assert "credentials_json" not in text and "workload_identity_provider" in text
    assert job


def test_flux_kustomization_points_at_k8s_app_and_prunes():
    docs = list(yaml.safe_load_all(open(ROOT / "cicd/flux/sync.yaml")))
    kz = next(d for d in docs if d["kind"] == "Kustomization")
    assert kz["spec"]["path"] == "./k8s/app" and kz["spec"]["prune"] is True
    assert kz["spec"]["sourceRef"]["name"] == next(d for d in docs if d["kind"] == "GitRepository")["metadata"]["name"]


def test_helm_chart_and_state_bucket_basics():
    chart = yaml.safe_load(open(ROOT / "charts/orders-api/Chart.yaml"))
    assert chart["name"] == "orders-api" and chart["apiVersion"] == "v2"
    bootstrap = open(ROOT / "terraform/bootstrap/main.tf").read()
    assert "versioning" in bootstrap and 'public_access_prevention    = "enforced"' in bootstrap
