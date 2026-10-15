"""Require resource metrics and an honest budget for a second API replica."""
import json
import subprocess
import time


def kube(*args):
    return json.loads(subprocess.check_output(["kubectl", *args, "-o", "json"]))


def quantity(value):
    units = {"Ki": 1024, "Mi": 1024**2, "Gi": 1024**3, "K": 1000, "M": 1000**2, "G": 1000**3, "m": 0.001}
    for unit, scale in units.items():
        if str(value).endswith(unit):
            return float(str(value)[:-len(unit)]) * scale
    return float(value)


def budget(node, pods, api_requests):
    requests = {"cpu": 0, "memory": 0}
    active_pods = 0
    for pod in pods:
        if pod["status"]["phase"] in ("Succeeded", "Failed"):
            continue
        active_pods += 1
        for resource in requests:
            regular = sum(quantity(c.get("resources", {}).get("requests", {}).get(resource, "0")) for c in pod["spec"]["containers"])
            init = max([quantity(c.get("resources", {}).get("requests", {}).get(resource, "0")) for c in pod["spec"].get("initContainers", [])] or [0])
            requests[resource] += max(regular, init)
    for resource, used in requests.items():
        needed = used + quantity(api_requests[resource])
        available = quantity(node["status"]["allocatable"][resource])
        if needed > available:
            raise ValueError(f"Second API replica exceeds node {resource} budget: {needed} > {available}")
    if active_pods + 1 > int(node["status"]["allocatable"]["pods"]):
        raise ValueError("No pod slot for the second API replica")
    return requests


def main():
    deadline = time.monotonic() + 600
    while True:
        hpa = kube("get", "hpa", "oficina-api", "-n", "oficina")
        metrics = hpa.get("status", {}).get("currentMetrics", [])
        active = any(c["type"] == "ScalingActive" and c["status"] == "True" for c in hpa.get("status", {}).get("conditions", []))
        deploy = kube("get", "deployment", "oficina-api", "-n", "oficina")
        if active and metrics and deploy["spec"]["replicas"] == 1 and deploy.get("status", {}).get("readyReplicas") == 1:
            break
        if time.monotonic() >= deadline:
            raise ValueError("HPA has no valid CPU metric or has not settled at one Ready replica")
        print("Waiting for CPU metrics and baseline of one Ready replica", flush=True)
        time.sleep(15)
    nodes = kube("get", "nodes")["items"]
    if len(nodes) != 1:
        raise ValueError("Unexpected node count")
    api = next(c for c in deploy["spec"]["template"]["spec"]["containers"] if c["name"] == "oficina-api")
    used = budget(nodes[0], kube("get", "pods", "-A")["items"], api["resources"]["requests"])
    print("OK second replica fits CPU, memory, and pod budget; HPA CPU metric available")
    print("Reserved before load:", json.dumps(used))


if __name__ == "__main__":
    main()
