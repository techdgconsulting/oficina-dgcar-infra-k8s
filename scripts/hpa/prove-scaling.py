"""Prove HPA 1 -> 2 Ready -> 1 on the SAME EC2, without scaling the Deployment.

Caps maxReplicas at 2 only for this bounded experiment and restores the original
HPA spec in finally. The HPA itself must initiate every replica change.
"""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def kube(*args):
    return json.loads(subprocess.check_output(["kubectl", *args, "-o", "json"]))


def patch_hpa(spec):
    subprocess.run(["kubectl", "patch", "hpa", "oficina-api", "-n", "oficina", "--type=merge",
                    "-p", json.dumps({"spec": spec})], check=True, stdout=subprocess.DEVNULL)


def sample():
    hpa = kube("get", "hpa", "oficina-api", "-n", "oficina")
    pods = kube("get", "pods", "-n", "oficina", "-l", "app.kubernetes.io/name=oficina-api")["items"]
    ready = [p for p in pods if not p["metadata"].get("deletionTimestamp") and p["status"]["phase"] == "Running" and any(
        c["type"] == "Ready" and c["status"] == "True" for c in p["status"].get("conditions", []))]
    for pod in pods:
        for container in pod["status"].get("containerStatuses", []):
            if container.get("restartCount", 0):
                raise ValueError("API restarted during load test")
    nodes = kube("get", "nodes")["items"]
    if len(nodes) != 1:
        raise ValueError("Test requires the original single node")
    if any(c["type"] == "MemoryPressure" and c["status"] == "True" for c in nodes[0]["status"]["conditions"]):
        raise ValueError("Node entered MemoryPressure")
    cpu = [m["resource"].get("current", {}).get("averageUtilization")
           for m in hpa.get("status", {}).get("currentMetrics", []) if m.get("resource", {}).get("name") == "cpu"]
    return {
        "time": datetime.now(timezone.utc).isoformat(),
        "ready": len(ready), "desired": hpa.get("status", {}).get("desiredReplicas"),
        "cpu_percent": cpu[0] if cpu else None,
        "node_uid": nodes[0]["metadata"]["uid"],
        "provider_id": nodes[0]["spec"]["providerID"],
        "pod_nodes": [p["spec"]["nodeName"] for p in ready],
        "pods": [p["metadata"]["name"] for p in ready],
    }


def main():
    output = Path(os.environ.get("HPA_RESULTS_DIR", "hpa-results"))
    output.mkdir(exist_ok=True)
    original = kube("get", "hpa", "oficina-api", "-n", "oficina")["spec"]
    (output / "hpa-original.json").write_text(json.dumps(original))
    initial = sample()
    if initial["ready"] != 1 or initial["cpu_percent"] is None:
        raise ValueError("Need exactly one Ready API pod and real CPU metrics before testing")
    service = kube("get", "service", "oficina-api", "-n", "oficina")
    environment = dict(os.environ, HPA_API_URL="http://" + service["status"]["loadBalancer"]["ingress"][0]["hostname"])
    observations = [initial]
    load = None
    try:
        patch_hpa({"minReplicas": 1, "maxReplicas": 2})
        with (output / "k6.log").open("w") as log:
            load = subprocess.Popen(["k6", "run", "--summary-export", str(output / "k6-summary.json"),
                                     str(Path(__file__).with_name("load.js"))], env=environment,
                                    stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 600
            consecutive = 0
            while time.monotonic() < deadline:
                current = sample()
                observations.append(current)
                if current["node_uid"] != initial["node_uid"]:
                    raise ValueError("Worker EC2 changed during test")
                print(json.dumps(current), flush=True)
                consecutive = consecutive + 1 if current["ready"] == 2 and current["desired"] == 2 else 0
                if consecutive >= 3:
                    break
                if load.poll() is not None:
                    raise ValueError("Load ended before two API pods became Ready")
                time.sleep(15)
            else:
                raise ValueError("HPA did not scale to two Ready pods under load")
            load.terminate()
            load.wait(timeout=30)
            load = None
        summary_path = output / "k6-summary.json"
        if not summary_path.exists():
            raise ValueError("k6 did not produce a load summary")
        metrics = json.loads(summary_path.read_text())["metrics"]
        failures = metrics["http_req_failed"]
        failures = failures.get("values", failures)
        rate = failures.get("rate", failures.get("value"))
        if rate is None or rate >= 0.01:
            raise ValueError("Load exceeded the allowed 1% HTTP error rate")
        deadline = time.monotonic() + 660
        while time.monotonic() < deadline:
            current = sample()
            observations.append(current)
            if current["node_uid"] != initial["node_uid"]:
                raise ValueError("Worker EC2 changed during recovery")
            print(json.dumps(current), flush=True)
            if current["ready"] == 1 and current["desired"] == 1:
                print("PASS: HPA 1 -> 2 Ready -> 1, same EC2; no Deployment scale command during load", flush=True)
                return
            time.sleep(15)
        raise ValueError("HPA did not return to one Ready pod after load ended")
    finally:
        if load is not None and load.poll() is None:
            load.terminate()
            load.wait(timeout=30)
        patch_hpa(original)
        (output / "scaling.json").write_text(json.dumps(observations, indent=2))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "restore":
        saved = Path(os.environ.get("HPA_RESULTS_DIR", "hpa-results")) / "hpa-original.json"
        if saved.exists():
            patch_hpa(json.loads(saved.read_text()))
    else:
        main()
