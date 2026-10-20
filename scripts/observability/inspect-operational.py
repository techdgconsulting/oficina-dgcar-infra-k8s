"""Read-only telemetry inventory; never print credentials or log messages."""
import importlib.util
import json
from pathlib import Path
import subprocess

spec = importlib.util.spec_from_file_location("business", Path(__file__).with_name("validate-business-dashboard.py"))
business = importlib.util.module_from_spec(spec)
spec.loader.exec_module(business)

queries = {
    "container fields": "FROM K8sContainerSample SELECT keyset() WHERE namespaceName = 'oficina' SINCE 30 minutes ago",
    "pod fields": "FROM K8sPodSample SELECT keyset() WHERE namespaceName = 'oficina' SINCE 30 minutes ago",
    "resources": "FROM K8sContainerSample SELECT latest(cpuLimitCores), latest(memoryLimitBytes), latest(cpuUsedCores), latest(memoryWorkingSetBytes), latest(isReady) WHERE clusterName = 'oficina-dgcar-homolog-eks' AND namespaceName = 'oficina' FACET podName, containerName SINCE 5 minutes ago",
    "log fields": "FROM Log SELECT keyset() WHERE entity.name = 'oficina-dgcar-api-homolog' OR application = 'oficina-mecanica-dgcar' OR namespace_name = 'oficina' SINCE 30 minutes ago",
    "log counts": "FROM Log SELECT count(*), filter(count(*), WHERE correlationId IS NOT NULL), filter(count(*), WHERE `trace.id` IS NOT NULL) WHERE entity.name = 'oficina-dgcar-api-homolog' OR namespace_name = 'oficina' SINCE 30 minutes ago",
    "synthetics": "FROM SyntheticCheck SELECT count(*) FACET monitorName SINCE 1 day ago",
    "API": "FROM Transaction SELECT count(*), percentile(duration, 95) WHERE appName = 'oficina-dgcar-api-homolog' SINCE 30 minutes ago",
}
for title, query in queries.items():
    print(title + ": " + json.dumps(business.execute_nrql(query)))

deployment = json.loads(subprocess.check_output(["kubectl", "get", "deployment", "oficina-api", "-n", "oficina", "-o", "json"]))
print("deployed resources: " + json.dumps([
    {"name": c["name"], "resources": c.get("resources", {})}
    for c in deployment["spec"]["template"]["spec"]["containers"]]))
config = json.loads(subprocess.check_output(["kubectl", "get", "configmap", "oficina-api-config", "-n", "oficina", "-o", "json"]))
print("logging configuration: " + json.dumps({k: v for k, v in config["data"].items()
    if k.startswith("NEW_RELIC_APPLICATION_LOGGING") or k == "NEW_RELIC_ENVIRONMENT"}))
