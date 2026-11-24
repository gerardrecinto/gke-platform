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
