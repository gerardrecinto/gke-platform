"""Capacity maths for GKE Standard.

Formulas:
- Allocatable CPU and memory: the reservation tiers in the GKE documentation.
- HPA: desired = ceil(current * metric / target), no change inside a 10% tolerance (Kubernetes default).
- VPA: a percentile of observed usage plus a safety margin. The real VPA uses decaying histograms; this is a simplified read.
- Cluster Autoscaler: pods are packed first-fit by requests; a node is added when pods are pending, up to the pool maximum.
"""
from __future__ import annotations

import math

# vCPU, memory in GiB
MACHINES = {
    "e2-standard-2": (2, 8),
    "e2-standard-4": (4, 16),
    "e2-standard-8": (8, 32),
    "n2-standard-4": (4, 16),
    "n2-standard-8": (8, 32),
}

MAX_PODS_PER_NODE = 110
EVICTION_MIB = 100
HPA_TOLERANCE = 0.1


def _tiered(total: float, tiers: list[tuple[float, float]], rest: float) -> float:
    """Sum rate * slice over consecutive slices; `rest` applies to everything above the tiers."""
    reserved, left = 0.0, total
    for size, rate in tiers:
        take = min(left, size)
        reserved += take * rate
        left -= take
        if left <= 0:
            return reserved
    return reserved + left * rest


def allocatable(vcpu: float, mem_gib: float) -> tuple[float, float]:
    """Return (cpu millicores, memory MiB) a pod can request on one node."""
    cpu_m = vcpu * 1000
    cpu_reserved = _tiered(cpu_m, [(1000, 0.06), (1000, 0.01), (2000, 0.005)], 0.0025)
    mem_mib = mem_gib * 1024
    if mem_mib < 1024:
        mem_reserved = 255.0
    else:
        gib = 1024
        mem_reserved = _tiered(
            mem_mib,
            [(4 * gib, 0.25), (4 * gib, 0.20), (8 * gib, 0.10), (112 * gib, 0.06)],
            0.02,
        )
    mem_reserved += EVICTION_MIB
    return round(cpu_m - cpu_reserved, 1), round(mem_mib - mem_reserved, 1)


def hpa_desired(current: int, metric: float, target: float, min_r: int = 1, max_r: int = 10) -> int:
    ratio = metric / target
    if abs(ratio - 1.0) <= HPA_TOLERANCE:
        desired = current
    else:
        desired = math.ceil(current * ratio)
    return max(min_r, min(max_r, desired))


def vpa_recommend(samples: list[float], percentile: float = 90, margin: float = 0.15) -> float:
    if not samples:
        raise ValueError("no samples")
    ordered = sorted(samples)
    rank = max(0, math.ceil(percentile / 100 * len(ordered)) - 1)
    return math.ceil(ordered[rank] * (1 + margin) * 10 - 1e-9) / 10  # round up: a request that is too low is the costly mistake


def nodes_needed(
    replicas: int,
    pod_cpu_m: float,
    pod_mem_mib: float,
    machine: str,
    zones: int = 3,
    min_per_zone: int = 1,
    max_per_zone: int = 4,
    daemonset_cpu_m: float = 0.0,
    daemonset_mem_mib: float = 0.0,
) -> dict:
    vcpu, gib = MACHINES[machine]
    cpu_a, mem_a = allocatable(vcpu, gib)
    cpu_a -= daemonset_cpu_m
    mem_a -= daemonset_mem_mib
    if pod_cpu_m > cpu_a or pod_mem_mib > mem_a:
        return {"fits": False, "reason": "one pod is larger than a node's allocatable", "nodes": 0}
    per_node = min(
        math.floor(cpu_a / pod_cpu_m) if pod_cpu_m else MAX_PODS_PER_NODE,
        math.floor(mem_a / pod_mem_mib) if pod_mem_mib else MAX_PODS_PER_NODE,
        MAX_PODS_PER_NODE,
    )
    wanted = math.ceil(replicas / per_node)
    # Regional pool: bounds apply per zone, and the BALANCED policy spreads nodes across zones.
    floor_nodes = min_per_zone * zones
    ceiling = max_per_zone * zones
    nodes = max(wanted, floor_nodes)
    scheduled = replicas
    pending = 0
    if nodes > ceiling:
        nodes = ceiling
        scheduled = nodes * per_node
        pending = replicas - scheduled
    used_cpu = min(replicas, scheduled) * pod_cpu_m
    return {
        "fits": True,
        "pods_per_node": per_node,
        "nodes": nodes,
        "pending_pods": pending,
        "cpu_requested_pct": round(100 * used_cpu / (nodes * (cpu_a + daemonset_cpu_m)), 1),
        "limited_by": "cpu" if per_node == math.floor(cpu_a / pod_cpu_m) else "memory",
        "allocatable_cpu_m": round(cpu_a + daemonset_cpu_m, 1),
        "allocatable_mem_mib": round(mem_a + daemonset_mem_mib, 1),
    }
