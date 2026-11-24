"""Cross-checks between manifests, and between manifests and Terraform. These catch the mistakes that only show up as a
silent 502 or an unhealthy backend in production."""
import glob
import pathlib
import re

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load_all():
    docs = []
    for f in glob.glob(str(ROOT / "k8s" / "**" / "*.yaml"), recursive=True):
        docs += [d for d in yaml.safe_load_all(open(f)) if d]
    return docs


def of(kind):
    return [d for d in load_all() if d["kind"] == kind]


def test_every_manifest_parses_and_has_a_namespace_or_is_cluster_scoped():
    for d in load_all():
        assert d.get("apiVersion") and d.get("kind") and d["metadata"].get("name")
        if d["kind"] != "Namespace":
            assert d["metadata"].get("namespace") == "orders", d["metadata"]["name"]


def test_hpa_targets_a_real_deployment_and_deployment_does_not_pin_replicas():
    dep = {d["metadata"]["name"]: d for d in of("Deployment")}
    for h in of("HorizontalPodAutoscaler"):
        assert h["spec"]["scaleTargetRef"]["name"] in dep
        assert h["spec"]["minReplicas"] >= 2, "one replica cannot survive a node drain"
    for d in dep.values():
        assert "replicas" not in d["spec"], "the HPA owns the replica count"


def test_pdb_and_service_select_the_deployment_pods():
    pods = of("Deployment")[0]["spec"]["template"]["metadata"]["labels"]
    for kind in ("PodDisruptionBudget",):
        sel = of(kind)[0]["spec"]["selector"]["matchLabels"]
        assert sel.items() <= pods.items()
    assert of("Service")[0]["spec"]["selector"].items() <= pods.items() if of("Service")[0]["spec"].get("selector") else True


def test_vpa_and_hpa_do_not_both_drive_cpu():
    vpa = of("VerticalPodAutoscaler")[0]
    cpu_hpa = [
        m for h in of("HorizontalPodAutoscaler") for m in h["spec"]["metrics"] if m["resource"]["name"] == "cpu"
    ]
    assert not cpu_hpa or vpa["spec"]["updatePolicy"]["updateMode"] == "Off"


def test_service_backendconfig_annotation_names_an_existing_backendconfig():
    svc = [s for s in of("Service") if s["metadata"]["name"] == "orders-api"][0]
    ref = re.search(r'"default":\s*"([^"]+)"', svc["metadata"]["annotations"]["cloud.google.com/backend-config"]).group(1)
    assert ref in {b["metadata"]["name"] for b in of("BackendConfig")}


def test_backendconfig_health_check_port_is_the_container_port():
    port = of("Deployment")[0]["spec"]["template"]["spec"]["containers"][0]["ports"][0]["containerPort"]
    assert of("BackendConfig")[0]["spec"]["healthCheck"]["port"] == port


def test_ingress_references_existing_service_cert_and_frontendconfig():
    ing = of("Ingress")[0]
    ann = ing["metadata"]["annotations"]
    assert ann["networking.gke.io/managed-certificates"] in {c["metadata"]["name"] for c in of("ManagedCertificate")}
    assert ann["networking.gke.io/v1beta1.FrontendConfig"] in {c["metadata"]["name"] for c in of("FrontendConfig")}
    svcs = {s["metadata"]["name"] for s in of("Service")}
    assert ing["spec"]["defaultBackend"]["service"]["name"] in svcs
    for r in ing["spec"]["rules"]:
        for p in r["http"]["paths"]:
            assert p["backend"]["service"]["name"] in svcs


def test_network_policy_allows_google_health_check_ranges():
    text = open(ROOT / "k8s/app/networkpolicy.yaml").read()
    assert "130.211.0.0/22" in text and "35.191.0.0/16" in text


def test_workload_identity_annotation_matches_terraform_names():
    sa = [s for s in of("ServiceAccount") if s["metadata"]["name"] == "orders-api"][0]
    email = sa["metadata"]["annotations"]["iam.gke.io/gcp-service-account"]
    tf = open(ROOT / "terraform/envs/dev/main.tf").read()
    gsa = re.search(r'google_sa_name\s*=\s*"([^"]+)"', tf).group(1)
    ksa = re.search(r'k8s_sa_name\s*=\s*"([^"]+)"', tf).group(1)
    ns = re.search(r'k8s_namespace\s*=\s*"([^"]+)"', tf).group(1)
    assert email.startswith(gsa + "@")
    assert (ksa, ns) == (sa["metadata"]["name"], sa["metadata"]["namespace"])


def test_every_container_sets_requests_and_drops_capabilities():
    for kind in ("Deployment", "StatefulSet"):
        for d in of(kind):
            for c in d["spec"]["template"]["spec"]["containers"]:
                assert "cpu" in c["resources"]["requests"] and "memory" in c["resources"]["requests"]
                assert c["securityContext"]["allowPrivilegeEscalation"] is False
                assert c["securityContext"]["capabilities"]["drop"] == ["ALL"]


def test_rbac_never_grants_wildcards_or_secrets():
    for r in of("Role"):
        for rule in r["rules"]:
            assert "*" not in rule["verbs"] + rule["resources"] + rule["apiGroups"]
            assert "secrets" not in rule["resources"]


def test_standard_cluster_has_autoscaling_workload_identity_and_vpa():
    tf = open(ROOT / "terraform/modules/gke-standard/main.tf").read()
    for needle in ("workload_identity_config", "vertical_pod_autoscaling", "autoscaling {", "enable_private_nodes", "ADVANCED_DATAPATH"):
        assert needle in tf
