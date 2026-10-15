"""Reject AWS/node/dashboard changes in an HPA support deployment."""
import json
import sys

ALLOWED = {
    "kubernetes_env.vpc_cni_prefix", "kubernetes_config_map_v1.node_pod_capacity",
    "kubernetes_job_v1.node_pod_capacity", "helm_release.metrics_server",
    "helm_release.new_relic_kubernetes",
}


def validate(plan):
    for change in plan.get("resource_changes", []):
        actions = change["change"]["actions"]
        if change["mode"] == "data" or actions == ["no-op"]:
            continue
        if change["address"] not in ALLOWED or "delete" in actions:
            raise ValueError("Unapproved HPA change: " + change["address"])
        print("OK HPA scope:", change["address"], actions)


if __name__ == "__main__":
    validate(json.load(open(sys.argv[1], encoding="utf-8")))
