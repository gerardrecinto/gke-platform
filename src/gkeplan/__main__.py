import argparse
import json

from .plan import MACHINES, allocatable, hpa_desired, nodes_needed, vpa_recommend


def main() -> None:
    p = argparse.ArgumentParser(prog="gkeplan", description="GKE capacity maths")
    sub = p.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("allocatable", help="what a node can give to pods")
    a.add_argument("machine", choices=sorted(MACHINES))

    h = sub.add_parser("hpa", help="desired replicas for a metric reading")
    h.add_argument("--current", type=int, required=True)
    h.add_argument("--metric", type=float, required=True, help="current average, same unit as target")
    h.add_argument("--target", type=float, required=True)
    h.add_argument("--min", type=int, default=1)
    h.add_argument("--max", type=int, default=10)

    v = sub.add_parser("vpa", help="request recommendation from usage samples")
    v.add_argument("samples", type=float, nargs="+")
    v.add_argument("--percentile", type=float, default=90)

    n = sub.add_parser("nodes", help="nodes the Cluster Autoscaler would settle on")
    n.add_argument("--replicas", type=int, required=True)
    n.add_argument("--cpu", type=float, required=True, help="request in millicores")
    n.add_argument("--mem", type=float, required=True, help="request in MiB")
    n.add_argument("--machine", choices=sorted(MACHINES), default="e2-standard-4")
    n.add_argument("--zones", type=int, default=3)
    n.add_argument("--min-per-zone", type=int, default=1)
    n.add_argument("--max-per-zone", type=int, default=4)

    args = p.parse_args()
    if args.cmd == "allocatable":
        cpu, mem = allocatable(*MACHINES[args.machine])
        out = {"machine": args.machine, "cpu_m": cpu, "mem_mib": mem}
    elif args.cmd == "hpa":
        out = {"desired": hpa_desired(args.current, args.metric, args.target, args.min, args.max)}
    elif args.cmd == "vpa":
        out = {"request": vpa_recommend(args.samples, args.percentile)}
    else:
        out = nodes_needed(args.replicas, args.cpu, args.mem, args.machine, args.zones, args.min_per_zone, args.max_per_zone)
    print(json.dumps(out, indent=2))
    raise SystemExit(1 if out.get("pending_pods") else 0)


main()
