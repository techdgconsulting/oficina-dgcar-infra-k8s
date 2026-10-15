"""Prepare one existing EC2 for prefix mode; never change instance type/count.

Only an unused, non-primary address belonging to the API pods deliberately paused
by this workflow may be released to make room for a /28 prefix.
"""
import json
from pathlib import Path
import subprocess
import sys
import time


def command(*args):
    return json.loads(subprocess.check_output(args))


def capture(destination):
    nodes = command("kubectl", "get", "nodes", "-o", "json")["items"]
    if len(nodes) != 1:
        raise ValueError("Expected exactly one existing node")
    pods = command("kubectl", "get", "pods", "-n", "oficina", "-l", "app.kubernetes.io/name=oficina-api", "-o", "json")["items"]
    result = {"instance_id": nodes[0]["spec"]["providerID"].rsplit("/", 1)[1],
              "api_ips": [p["status"]["podIP"] for p in pods if p["status"].get("podIP") and not p["spec"].get("hostNetwork")]}
    destination.parent.mkdir(exist_ok=True)
    destination.write_text(json.dumps(result))


def releasable(interfaces, candidates, active):
    for interface in interfaces:
        for address in interface.get("PrivateIpAddresses", []):
            ip = address["PrivateIpAddress"]
            if ip in candidates and ip not in active and not address.get("Primary", False):
                return interface["NetworkInterfaceId"], ip
    return None


def ensure(snapshot):
    saved = json.loads(snapshot.read_text())

    def interfaces():
        return command("aws", "ec2", "describe-network-interfaces", "--filters",
                       "Name=attachment.instance-id,Values=" + saved["instance_id"],
                       "--output", "json")["NetworkInterfaces"]

    def prefix_present():
        return any(i.get("Ipv4Prefixes") for i in interfaces())

    subprocess.run(["kubectl", "rollout", "status", "daemonset/aws-node", "-n", "kube-system", "--timeout=180s"], check=True)
    for _ in range(6):
        if prefix_present():
            print("OK prefix delegated to the existing EC2")
            return
        time.sleep(10)
    active = {ip["ip"] for p in command("kubectl", "get", "pods", "-A", "-o", "json")["items"]
              if p["status"]["phase"] not in ("Succeeded", "Failed") for ip in p["status"].get("podIPs", [])}
    candidate = releasable(interfaces(), set(saved["api_ips"]), active)
    if candidate is None:
        raise ValueError("No prefix and no safely releasable former API address; node left unchanged")
    subprocess.run(["aws", "ec2", "unassign-private-ip-addresses", "--network-interface-id", candidate[0],
                    "--private-ip-addresses", candidate[1]], check=True)
    print("Released only the unused former API address to free a prefix slot")
    subprocess.run(["kubectl", "rollout", "restart", "daemonset/aws-node", "-n", "kube-system"], check=True)
    subprocess.run(["kubectl", "rollout", "status", "daemonset/aws-node", "-n", "kube-system", "--timeout=180s"], check=True)
    for _ in range(18):
        if prefix_present():
            print("OK prefix delegated to the same EC2 after legacy address cleanup")
            return
        time.sleep(10)
    raise ValueError("VPC CNI did not allocate an IPv4 prefix")


if __name__ == "__main__":
    destination = Path("hpa-results/network-before.json")
    if sys.argv[1] == "capture":
        capture(destination)
    elif sys.argv[1] == "ensure":
        ensure(destination)
    else:
        raise ValueError("Expected capture or ensure")
