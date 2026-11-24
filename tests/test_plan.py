import pytest

from gkeplan import MACHINES, allocatable, hpa_desired, nodes_needed, vpa_recommend


def test_allocatable_matches_gke_docs_cpu():
    # GKE documents 3920m for a 4 vCPU node and 7910m for 8 vCPU.
    assert allocatable(4, 16)[0] == 3920
    assert allocatable(8, 32)[0] == 7910
    assert allocatable(2, 8)[0] == 1930


def test_allocatable_memory_tiers():
    # 16 GiB: 25% of 4 GiB + 20% of 4 GiB + 10% of 8 GiB + 100 MiB eviction.
    assert allocatable(4, 16)[1] == pytest.approx(16384 - (1024 + 819.2 + 819.2 + 100), abs=0.1)


def test_allocatable_small_node_uses_flat_reservation():
    assert allocatable(1, 0.5)[1] == pytest.approx(512 - 255 - 100)


@pytest.mark.parametrize(
    "current,metric,target,expected",
    [
        (4, 100, 50, 8),  # double the load, double the pods
        (4, 52, 50, 4),  # inside the 10% tolerance: no change
        (4, 25, 50, 2),
        (4, 400, 50, 10),  # clamped to max
        (4, 1, 50, 1),  # clamped to min
    ],
)
def test_hpa_desired(current, metric, target, expected):
    assert hpa_desired(current, metric, target, 1, 10) == expected


def test_vpa_uses_percentile_and_margin():
    samples = [100] * 9 + [1000]
    assert vpa_recommend(samples, 90) == pytest.approx(115.0)  # p90 is 100, margin 15%
    assert vpa_recommend(samples, 100) == pytest.approx(1150.0)


def test_vpa_rejects_empty():
    with pytest.raises(ValueError):
        vpa_recommend([])


def test_nodes_needed_packs_by_the_tighter_resource():
    r = nodes_needed(40, 500, 512, "e2-standard-4", zones=3, min_per_zone=1, max_per_zone=4)
    assert r["pods_per_node"] == 7 and r["limited_by"] == "cpu"
    assert r["nodes"] == 6 and r["pending_pods"] == 0


def test_nodes_needed_respects_minimum_per_zone():
    assert nodes_needed(1, 100, 64, "e2-standard-4", zones=3, min_per_zone=1)["nodes"] == 3


def test_nodes_needed_reports_pending_pods_at_the_ceiling():
    r = nodes_needed(200, 500, 512, "e2-standard-4", zones=3, max_per_zone=2)
    assert r["nodes"] == 6 and r["pending_pods"] == 200 - 6 * 7


def test_pod_larger_than_a_node_does_not_fit():
    assert nodes_needed(1, 4000, 64, "e2-standard-4")["fits"] is False


def test_machine_table_is_sane():
    assert all(v > 0 and m > 0 for v, m in MACHINES.values())
