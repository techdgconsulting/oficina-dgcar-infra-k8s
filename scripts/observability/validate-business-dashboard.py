"""Validate a targeted dashboard plan and compile its NRQL using NerdGraph.

Only widget titles, result row counts and numeric cards are printed.
Customer/order payloads and API credentials are never printed.
"""
import json
import os
import sys
import urllib.request


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
    print(f"Validated {len(queries)} widget queries")


if __name__ == "__main__":
    main()
