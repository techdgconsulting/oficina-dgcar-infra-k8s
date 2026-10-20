"""Deployment routing and non-destructive Terraform guards. No credentials are logged."""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

CENTRAL = "techdgconsulting/oficina-dgcar-infra-k8s"
COMPONENTS = {
    "api": ("oficina-dgcar-api", "app-cd.yml", ""),
    "database": ("oficina-dgcar-infra-db", "terraform.yml", "apply"),
    "lambda": ("oficina-dgcar-auth-lambda", "ci.yml", "apply-infra"),
    "lambda-code": ("oficina-dgcar-auth-lambda", "ci.yml", "deploy-code"),
}

def gh(*args):
    return subprocess.check_output(["gh", *args], text=True).strip()

def pair(environment, branch):
    if {"homolog": "homolog", "prod": "main"}.get(environment) != branch:
        raise ValueError("Ambiente e branch incompatíveis: homolog/homolog ou prod/main são obrigatórios.")

def sha(value):
    if not re.fullmatch(r"[0-9a-f]{40}", value or ""):
        raise ValueError("Informe o SHA completo do commit validado.")
    return value

def non_destructive(plan):
    changes = plan.get("resource_changes", [])
    blocked = [c["address"] for c in changes if "delete" in c["change"]["actions"]]
    if blocked:
        raise ValueError("Plano bloqueado: remoção ou substituição exige revisão e aprovação explícita: " + ", ".join(blocked))
    if plan.get("errored") or plan.get("complete") is False:
        raise ValueError("Plano incompleto ou com erros; não será aplicado.")
    return len([c for c in changes if c["change"]["actions"] != ["no-op"]])

def verify_parent(run, environment, branch, action):
    expected = "destroy" if action in ("destroy", "destroy-infra") else "provision"
    if run.get("status") != "in_progress":
        raise ValueError("O coordenador precisa estar em execução.")
    if run.get("path", "").split("@", 1)[0] != f".github/workflows/{expected}-{environment}.yml":
        raise ValueError("Workflow coordenador incompatível com a operação.")
    # The existing manual destroy workflow is dispatched on the default branch.
    allowed_branch = "main" if expected == "destroy" else branch
    if run.get("head_branch") != allowed_branch or run.get("event") not in ("push", "workflow_dispatch"):
        raise ValueError("Branch ou evento do coordenador inválido.")
    if expected == "destroy" and run.get("event") != "workflow_dispatch":
        raise ValueError("Destroy exige acionamento manual do coordenador.")

def worker():
    env, branch = os.environ["TARGET_ENVIRONMENT"], os.environ["GITHUB_REF_NAME"]
    action = os.environ.get("DEPLOY_ACTION", "")
    if action not in ("destroy", "destroy-infra"):
        pair(env, branch)
    elif branch not in ("main", "homolog"):
        raise ValueError("Destroy só pode usar uma branch protegida.")
    parent = os.environ.get("PARENT_RUN_ID", "")
    if not parent.isdigit():
        raise ValueError("Operação deve ser solicitada pelo coordenador de ambiente.")
    run = json.loads(gh("api", f"repos/{CENTRAL}/actions/runs/{parent}"))
    verify_parent(run, env, branch, action)
    source = sha(os.environ["SOURCE_SHA"])
    # The checked-out and tested source must belong to the requested protected branch.
    repo = os.environ["GITHUB_REPOSITORY"]
    if action not in ("destroy", "destroy-infra"):
        component = next((key for key, value in COMPONENTS.items()
                          if repo == "techdgconsulting/" + value[0] and (value[2] or "deploy") == action), None)
        title = run.get("display_title", "")
        if "| all |" not in title and f"| {component} | {source}" not in title:
            raise ValueError("Coordenador não corresponde ao componente e commit solicitados.")
    compared = json.loads(gh("api", f"repos/{repo}/compare/{source}...{branch}"))
    if compared["status"] not in ("ahead", "identical"):
        raise ValueError("Commit não pertence ao histórico da branch de destino.")
    print(f"Coordenador {parent} autorizado para {env}; commit {source}.")

def request():
    env, branch = os.environ["TARGET_ENVIRONMENT"], os.environ["GITHUB_REF_NAME"]
    pair(env, branch)
    component = os.environ["COMPONENT"]
    if component not in COMPONENTS:
        raise ValueError("Componente desconhecido.")
    source = sha(os.environ["SOURCE_SHA"])
    gh("workflow", "run", f"provision-{env}.yml", "--repo", CENTRAL, "--ref", branch,
       "-f", f"component={component}", "-f", f"source_sha={source}")
    print(f"Atualização de {component} enviada à fila de {env}: {source}.")

def main():
    if sys.argv[1] == "plan":
        count = non_destructive(json.loads(Path(sys.argv[2]).read_text(encoding="utf-8")))
        print(f"Plano validado: {count} alterações, sem remoções ou substituições.")
    elif sys.argv[1] == "worker":
        worker()
    elif sys.argv[1] == "request":
        request()
    else:
        raise ValueError("Comando inválido.")

if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
