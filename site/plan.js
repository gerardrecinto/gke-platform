// Browser port of src/gkeplan/plan.py. tests/fixtures/golden.json is generated from the Python and checked by node --test.
(function (root) {
  const MACHINES = { "e2-standard-2": [2, 8], "e2-standard-4": [4, 16], "e2-standard-8": [8, 32], "n2-standard-4": [4, 16], "n2-standard-8": [8, 32] };
  const MAX_PODS = 110, EVICT = 100, TOL = 0.1;

  function tiered(total, tiers, rest) {
    let reserved = 0, left = total;
    for (const [size, rate] of tiers) {
      const take = Math.min(left, size);
      reserved += take * rate; left -= take;
      if (left <= 0) return reserved;
    }
    return reserved + left * rest;
  }
  const r1 = (x) => Math.round(x * 10) / 10;

  function allocatable(vcpu, gib) {
    const cpu = vcpu * 1000;
    const cpuRes = tiered(cpu, [[1000, 0.06], [1000, 0.01], [2000, 0.005]], 0.0025);
    const mem = gib * 1024;
    const G = 1024;
    const memRes = (mem < 1024 ? 255 : tiered(mem, [[4 * G, 0.25], [4 * G, 0.2], [8 * G, 0.1], [112 * G, 0.06]], 0.02)) + EVICT;
    return [r1(cpu - cpuRes), r1(mem - memRes)];
  }

  function hpaDesired(current, metric, target, min = 1, max = 10) {
    const ratio = metric / target;
    const d = Math.abs(ratio - 1) <= TOL ? current : Math.ceil(current * ratio);
    return Math.max(min, Math.min(max, d));
  }

  function vpaRecommend(samples, pct = 90, margin = 0.15) {
    const s = [...samples].sort((a, b) => a - b);
    const rank = Math.max(0, Math.ceil((pct / 100) * s.length) - 1);
    return Math.ceil(s[rank] * (1 + margin) * 10 - 1e-9) / 10;
  }

  function nodesNeeded(o) {
    const { replicas, podCpu, podMem, machine, zones = 3, minPerZone = 1, maxPerZone = 4 } = o;
    const [v, g] = MACHINES[machine];
    const [cpuA, memA] = allocatable(v, g);
    if (podCpu > cpuA || podMem > memA) return { fits: false, nodes: 0 };
    const perNode = Math.min(Math.floor(cpuA / podCpu), Math.floor(memA / podMem), MAX_PODS);
    const wanted = Math.ceil(replicas / perNode);
    const ceiling = maxPerZone * zones;
    let nodes = Math.max(wanted, minPerZone * zones), scheduled = replicas, pending = 0;
    if (nodes > ceiling) { nodes = ceiling; scheduled = nodes * perNode; pending = replicas - scheduled; }
    return {
      fits: true, pods_per_node: perNode, nodes, pending_pods: pending,
      cpu_requested_pct: r1((100 * Math.min(replicas, scheduled) * podCpu) / (nodes * cpuA)),
      limited_by: perNode === Math.floor(cpuA / podCpu) ? "cpu" : "memory",
      allocatable_cpu_m: r1(cpuA), allocatable_mem_mib: r1(memA),
    };
  }

  const api = { MACHINES, allocatable, hpaDesired, vpaRecommend, nodesNeeded };
  if (typeof module !== "undefined") module.exports = api; else root.GKEPlan = api;
})(typeof window !== "undefined" ? window : globalThis);
