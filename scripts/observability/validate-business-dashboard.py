"""Validate a targeted dashboard plan and compile its NRQL using NerdGraph.

Only widget titles, result row counts and numeric cards are printed.
Customer/order payloads and API credentials are never printed.
"""
import json
import math
import os
import re
import sys
import urllib.request
from collections import Counter, defaultdict
from datetime import datetime, timezone


def validate_scope(plan):
    changes = plan.get("resource_changes", [])
    for change in changes:
        actions = change["change"]["actions"]
        if actions != ["no-op"]:
            if change["address"] != "newrelic_one_dashboard.business[0]" or "delete" in actions:
                raise ValueError("Plan contains a change outside the business dashboard")
    return next(c["change"]["after"] for c in changes
                if c["address"] == "newrelic_one_dashboard.business[0]")


def widgets(dashboard):
    for page in dashboard["page"]:
        for key, entries in page.items():
            if key.startswith("widget_") and isinstance(entries, list):
                for widget in entries:
                    for query in widget.get("nrql_query", []):
                        yield widget["title"], query["query"]


def execute_nrql(query):
    account = int(os.environ["NEW_RELIC_ACCOUNT_ID"])
    graphql = ("{ actor { account(id: " + str(account)
               + ") { nrql(query: " + json.dumps(query)
               + ", timeout: 60) { results } } } }")
    request = urllib.request.Request(
        "https://api.newrelic.com/graphql",
        data=json.dumps({"query": graphql}).encode(),
        headers={"API-Key": os.environ["NEW_RELIC_API_KEY"], "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=75) as response:
        payload = json.load(response)
    if payload.get("errors"):
        raise ValueError("New Relic rejected NRQL: " + json.dumps(payload["errors"]))
    return payload["data"]["actor"]["account"]["nrql"]["results"]


def read_orders():
    base = os.environ["DASHBOARD_VALIDATION_API_URL"].rstrip("/")
    login = urllib.request.Request(base + "/api/auth/login", data=json.dumps({
        "username": "Patricia Almeida", "password": "senha123"
    }).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(login, timeout=30) as response:
        token = json.load(response)["token"]
    request = urllib.request.Request(base + "/api/ordens-servico", headers={"Authorization": "Bearer " + token})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def facet(row):
    value = row["facet"]
    return value if isinstance(value, list) else [value]


def api_epoch(value):
    data = datetime.fromisoformat(value.replace("Z", "+00:00"))
    # A API Docker grava LocalDateTime em UTC; a apresentacao usa America/Sao_Paulo.
    if data.tzinfo is None:
        data = data.replace(tzinfo=timezone.utc)
    return round(data.timestamp() * 1000)


def validate_business_values(queries):
    by_title = dict(queries)
    table = execute_nrql(by_title["Ordens de servico"])
    if any("timestamp" in {key.lower() for key in row} for row in table):
        raise ValueError("Ordens de servico ainda retorna a coluna tecnica timestamp")
    columns = {"Cliente", "Veiculo", "Placa", "Mecanico", "Status", "Data de entrega", "Valor"}
    if any(not columns.issubset(row) for row in table):
        raise ValueError("A tabela perdeu uma coluna autorizada")
    print("OK schema da tabela: mesmas colunas de negocio, sem timestamp")

    app = re.search(r"app_name = '([^']+)'", by_title["Produtividade por mecanico"]).group(1)
    source = f"app_name = '{app}'"
    historical = execute_nrql(
        "FROM OficinaOsStatusDurationSnapshot SELECT latest(tempo_ms) AS tempo_ms "
        f"WHERE {source} AND numero_os LIKE 'OS-HIST-%' "
        "FACET numero_os, status, inicio_ms SINCE 30 minutes ago LIMIT MAX")
    expected_ms = {"EM_DIAGNOSTICO": 3600000, "EM_EXECUCAO": 511200000, "FINALIZADA": 3600000}
    historical_orders = defaultdict(set)
    for row in historical:
        numero, status, _ = facet(row)
        if row["tempo_ms"] != expected_ms[status]:
            raise ValueError("Intervalo historico difere das datas persistidas da massa")
        historical_orders[numero].add(status)
    if len(historical_orders) < 7 or any(statuses != set(expected_ms) for statuses in historical_orders.values()):
        raise ValueError("Os tres intervalos das sete OS historicas ainda nao chegaram ao New Relic")
    print("OK massa historica: Diagnostico=60 min, Execucao=8520 min, Finalizacao=60 min por OS")

    orders = read_orders()
    end = int(datetime.now(timezone.utc).timestamp()) * 1000
    for days in (1, 14):
        start = end - days * 86400000
        period = f"SINCE {start} UNTIL {end}"
        bounds = execute_nrql(
            "FROM OficinaOsOperationalSnapshot SELECT aggregationendtime() AS fim, "
            "aggregationendtime() - round(count(*) / rate(count(*), 1 second) * 1000) AS inicio "
            f"WHERE {source} {period}")[0]
        if abs(bounds["inicio"] - start) > 1 or abs(bounds["fim"] - end) > 1:
            raise ValueError("Limites calculados nao correspondem ao periodo consultado")

        expected = Counter()
        for order in orders:
            mechanic = order.get("mecanicoNome")
            completed = order.get("dataFinalizacao")
            if (order["status"] in ("FINALIZADA", "AGUARDANDO_RETIRADA", "ENTREGUE")
                    and mechanic and mechanic not in ("NAO_INFORMADO", "NAO_ATRIBUIDO")
                    and completed and start <= api_epoch(completed) < end):
                expected[mechanic] += 1
        productivity = execute_nrql(by_title["Produtividade por mecanico"].replace("SINCE 1 day ago", period))
        actual = {facet(row)[0]: row["OS finalizadas"] for row in productivity}
        if actual != dict(expected):
            raise ValueError(f"Produtividade de {days} dias diverge da contagem de OS finalizadas da API")
        print(f"OK produtividade {days} dias: {sum(actual.values())} OS; todos os mecanicos conferem com a API")

        # Cada intervalo e amostrado uma unica vez, independentemente dos ciclos do agendador.
        intervals = execute_nrql(
            "FROM OficinaOsStatusDurationSnapshot SELECT latest(tempo_ms) AS tempo_ms, latest(fim_ms) AS fim_ms "
            f"WHERE {source} FACET numero_os, status, inicio_ms {period} LIMIT MAX")
        samples = defaultdict(list)
        for row in intervals:
            if start <= row["fim_ms"] < end:
                samples[facet(row)[1]].append(row["tempo_ms"] / 60000)
        averages = execute_nrql(by_title["Tempo medio de execucao por status"].replace("SINCE 1 day ago", period))
        actual_means = {facet(row)[0]: row["Minutos"] for row in averages}
        expected_means = {status: sum(values) / len(values) for status, values in samples.items()}
        if set(actual_means) != set(expected_means) or any(
                not math.isclose(actual_means[status], value, rel_tol=1e-8, abs_tol=1e-8)
                for status, value in expected_means.items()):
            raise ValueError(f"Media por status de {days} dias diverge dos intervalos unicos persistidos")
        print(f"OK medias {days} dias: {actual_means}")


def main():
    with open(sys.argv[1], encoding="utf-8") as source:
        dashboard = validate_scope(json.load(source))
    queries = list(widgets(dashboard))
    if not queries:
        raise ValueError("Business dashboard contains no queries")
    for title, query in queries:
        results = execute_nrql(query)
        numeric_cards = [{k: v for k, v in row.items() if isinstance(v, (int, float))}
                         for row in results]
        print(f"OK {title}: {len(results)} rows; numeric values={numeric_cards}")
    validate_business_values(queries)
    print(f"Validated {len(queries)} widget queries")


if __name__ == "__main__":
    main()
