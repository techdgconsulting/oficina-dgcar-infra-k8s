"""Validate the approved operational scope and compare telemetry with Kubernetes.

Never prints tokens, customer data, log messages, state or secret values.
"""
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request
import uuid

spec = importlib.util.spec_from_file_location("business", Path(__file__).with_name("validate-business-dashboard.py"))
business = importlib.util.module_from_spec(spec)
spec.loader.exec_module(business)
nrql = business.execute_nrql

ALLOWED = {
    "newrelic_one_dashboard.operational[0]",
    "newrelic_synthetics_monitor.api_health[0]",
    "newrelic_nrql_alert_condition.external_health[0]",
    "newrelic_nrql_alert_condition.os_processing_failure[0]",
    "newrelic_nrql_alert_condition.health_down[0]",
    "helm_release.new_relic_kubernetes[0]",
}
LEGACY = {"newrelic_one_dashboard.api[0]", "newrelic_one_dashboard.kubernetes[0]"}
K8S = "clusterName = 'oficina-dgcar-homolog-eks' AND namespaceName = 'oficina'"
LOG = "cluster_name = 'oficina-dgcar-homolog-eks' AND namespace_name = 'oficina' AND container_name = 'oficina-api' AND environment = 'homolog'"


def kubectl(*args):
    return json.loads(subprocess.check_output(["kubectl", *args, "-o", "json"]))


def validate_plan(plan):
    retire = os.environ.get("OPERATIONAL_PHASE") == "retire"
    for change in plan.get("resource_changes", []):
        actions = change["change"]["actions"]
        if actions == ["no-op"] or change["mode"] == "data":
            continue
        address = change["address"]
        if retire:
            if address not in LEGACY or actions != ["delete"]:
                raise ValueError("Retirement plan changes a resource outside the two old dashboards")
        elif address not in ALLOWED or "delete" in actions:
            raise ValueError("Operational plan changes an unapproved resource: " + address)
        print("OK scope: " + address + " " + ",".join(actions))
    if retire:
        return
    dashboard = next(c["change"]["after"] for c in plan["resource_changes"]
                     if c["address"] == "newrelic_one_dashboard.operational[0]")
    queries = list(business.widgets(dashboard))
    if len(queries) != 15:
        raise ValueError("Unexpected operational widget count")
    for title, query in queries:
        for variable in ("pod", "level", "correlation"):
            query = query.replace("{{" + variable + "}}", "'%'")
        nrql(query)
        print("OK NRQL: " + title)
    print("OK business dashboard excluded from operational plan")


def cpu_cores(value):
    return float(value[:-1]) / 1000 if value.endswith("m") else float(value)


def bytes_quantity(value):
    factors = {"Ki": 1024, "Mi": 1024**2, "Gi": 1024**3}
    for suffix, factor in factors.items():
        if value.endswith(suffix):
            return float(value[:-2]) * factor
    return float(value)


def wait_for(description, check, timeout=240):
    deadline = time.monotonic() + timeout
    while True:
        if check():
            print("OK " + description)
            return
        if time.monotonic() >= deadline:
            raise ValueError("Timed out: " + description)
        print("Waiting: " + description, flush=True)
        time.sleep(15)


def validate_live():
    pods = kubectl("get", "pods", "-n", "oficina", "-l", "app.kubernetes.io/name=oficina-api")["items"]
    active = {p["metadata"]["name"] for p in pods if p["status"]["phase"] == "Running" and any(
        c["type"] == "Ready" and c["status"] == "True" for c in p["status"].get("conditions", []))}
    if not active:
        raise ValueError("API has no active pods")
    query = ("FROM (FROM K8sPodSample SELECT latest(status) AS estado, latest(isReady) AS pronto "
             f"WHERE {K8S} AND podName LIKE 'oficina-api-%' FACET podName LIMIT MAX) "
             "SELECT filter(count(*), WHERE estado = 'Running' AND pronto = 1) AS ativos SINCE 3 minutes ago")
    wait_for("active pods match Kubernetes (" + str(len(active)) + ")",
             lambda: nrql(query)[0]["ativos"] == len(active))

    samples = nrql("FROM K8sContainerSample SELECT latest(cpuLimitCores) AS cpu, "
                   "latest(memoryLimitBytes) AS memoria "
                   f"WHERE {K8S} AND containerName = 'oficina-api' FACET podName SINCE 3 minutes ago LIMIT MAX")
    observed = {business.facet(row)[0]: row for row in samples}
    for pod in pods:
        name = pod["metadata"]["name"]
        if name not in active:
            continue
        limits = next(c["resources"]["limits"] for c in pod["spec"]["containers"] if c["name"] == "oficina-api")
        if name not in observed or not math.isclose(observed[name]["cpu"], cpu_cores(limits["cpu"])) or not math.isclose(
                observed[name]["memoria"], bytes_quantity(limits["memory"])):
            raise ValueError("Resource maximum lines do not match deployed limits")
        print(f"OK resource lines: CPU={observed[name]['cpu']} cores; memory={observed[name]['memoria'] / 1048576} MiB")

    config = kubectl("get", "configmap", "oficina-api-config", "-n", "oficina")["data"]
    if config.get("NEW_RELIC_APPLICATION_LOGGING_FORWARDING_ENABLED") != "false":
        raise ValueError("Java forwarding must be disabled before validating the single collector")
    wait_for("external health checks ingested", lambda: bool(nrql(
        "FROM SyntheticCheck SELECT count(*) AS checks WHERE monitorName = 'oficina-dgcar-homolog - Health API' SINCE 10 minutes ago")[0]["checks"]))
    health = nrql("FROM SyntheticCheck SELECT latest(result) AS result, percentage(count(*), WHERE result = 'SUCCESS') AS uptime "
                  "WHERE monitorName = 'oficina-dgcar-homolog - Health API' SINCE 10 minutes ago")[0]
    if health["result"] != "SUCCESS":
        raise ValueError("External readiness is failing")
    print("OK external health: " + json.dumps(health))

    # Read-only requests, same supplied correlation ID; no business data is created.
    svc = kubectl("get", "service", "oficina-api", "-n", "oficina")
    base = "http://" + svc["status"]["loadBalancer"]["ingress"][0]["hostname"]
    correlation = "dashboard-check-" + uuid.uuid4().hex
    for _ in range(2):
        request = urllib.request.Request(base + "/api-docs", headers={"X-Correlation-Id": correlation})
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.headers.get("X-Correlation-Id") != correlation:
                raise ValueError("Response lost correlation header")
            response.read()

    def logs_received():
        rows = nrql(f"FROM Log SELECT count(*) AS logs, uniqueCount(`trace.id`) AS traces "
                    f"WHERE {LOG} AND correlationId = '{correlation}' AND message = 'http_request_completed' SINCE 10 minutes ago")
        return rows[0]["logs"] >= 2 and rows[0]["traces"] == 2

    wait_for("two requests found by correlation ID with distinct traces", logs_received)
    logs = nrql("FROM Log SELECT count(*) AS logs, uniqueCount(`trace.id`) AS traces, "
                "filter(count(*), WHERE requestMethod = 'GET' AND requestUri = '/api-docs' AND statusCode = '200' "
                "AND elapsedMs IS NOT NULL AND pod_name IS NOT NULL AND level = 'INFO') AS structured "
                f"WHERE {LOG} AND correlationId = '{correlation}' AND message = 'http_request_completed' SINCE 10 minutes ago")[0]
    if logs["logs"] != 2 or logs["structured"] != 2:
        raise ValueError("Logs duplicated or expected JSON fields missing")
    transactions = nrql("FROM Transaction SELECT count(*) AS requests WHERE appName = 'oficina-dgcar-api-homolog' "
                        f"AND correlationId = '{correlation}' SINCE 10 minutes ago")[0]
    if transactions["requests"] != 2:
        raise ValueError("Correlation ID not found on both APM transactions")
    print("OK JSON fields, pod context, APM correlation and no duplicate request logs: " + json.dumps(logs))


if __name__ == "__main__":
    with open(sys.argv[2], encoding="utf-8") as source:
        plan = json.load(source)
    if sys.argv[1] == "plan":
        validate_plan(plan)
    elif sys.argv[1] == "live":
        validate_live()
    else:
        raise ValueError("Expected plan or live")
