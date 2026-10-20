"""Validate and dispatch a single component while holding the environment queue."""
import json
import os
import subprocess
import sys
from deployment import CENTRAL, COMPONENTS, gh, pair, sha

def validate():
    environment = os.environ["TARGET_ENVIRONMENT"]
    branch = os.environ["GITHUB_REF_NAME"]
    pair(environment, branch)
    component = os.environ["COMPONENT"]
    if component != "platform" and component not in COMPONENTS:
        raise ValueError("Componente inválido.")
    source = sha(os.environ["DEPLOY_SOURCE_SHA"])
    repo = CENTRAL if component == "platform" else "techdgconsulting/" + COMPONENTS[component][0]
    compared = json.loads(gh("api", f"repos/{repo}/compare/{source}...{branch}"))
    if compared["status"] not in ("ahead", "identical"):
        raise ValueError("Commit de origem não pertence à branch protegida do ambiente.")
    print(f"Atualização validada: {component}, {environment}, {source}.")

def dispatch():
    validate()
    repo, workflow, action = COMPONENTS[os.environ["COMPONENT"]]
    args = ["techdgconsulting/" + repo, workflow, os.environ["GITHUB_REF_NAME"]]
    fields = ["-f", "environment=" + os.environ["TARGET_ENVIRONMENT"]]
    if action:
        fields.extend(["-f", "action=" + action])
    subprocess.run(["bash", "scripts/github-actions/dispatch-workflow.sh", *args, *fields], check=True)
    subprocess.run(["bash", "scripts/github-actions/wait-workflow.sh", *args], check=True)

if __name__ == "__main__":
    try:
        {"validate": validate, "dispatch": dispatch}[sys.argv[1]]()
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
