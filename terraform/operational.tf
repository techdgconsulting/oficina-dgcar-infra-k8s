locals {
  nrql_operational_containers = "${local.nrql_k8s_app} AND containerName = 'oficina-api' AND podName LIKE 'oficina-api-%'"
  nrql_operational_pods       = "${local.nrql_k8s_app} AND podName LIKE 'oficina-api-%'"
  nrql_operational_logs       = "cluster_name = '${local.new_relic_cluster_name}' AND namespace_name = '${local.new_relic_namespace_app}' AND container_name = 'oficina-api' AND environment = '${var.environment}'"
  nrql_operational_synthetic  = "monitorName = '${local.name} - Health API'"
}

resource "newrelic_synthetics_monitor" "api_health" {
  count = local.new_relic_observability_enabled ? 1 : 0

  account_id                = var.new_relic_account_id
  name                      = "${local.name} - Health API"
  status                    = "ENABLED"
  type                      = "SIMPLE"
  period                    = "EVERY_MINUTE"
  uri                       = "${aws_apigatewayv2_api.main[0].api_endpoint}/actuator/health/readiness"
  locations_public          = ["US_EAST_1"]
  bypass_head_request       = true
  treat_redirect_as_failure = true
  validation_string         = "\"status\":\"UP\""
  verify_ssl                = true
}

resource "newrelic_one_dashboard" "operational" {
  count = local.new_relic_observability_enabled ? 1 : 0

  name        = "${local.name} - API e Kubernetes"
  permissions = "public_read_only"

  variable {
    name                 = "pod"
    title                = "Pod (recursos e logs)"
    type                 = "string"
    default_values       = ["%"]
    replacement_strategy = "string"
  }
  variable {
    name                 = "level"
    title                = "Nivel do log"
    type                 = "string"
    default_values       = ["%"]
    replacement_strategy = "string"
  }
  variable {
    name                 = "correlation"
    title                = "Correlation ID (logs)"
    type                 = "string"
    default_values       = ["%"]
    replacement_strategy = "string"
  }

  page {
    name = "API e Kubernetes"

    widget_billboard {
      title             = "Pods ativos (Running e Ready - ultimos 3 min)"
      ignore_time_range = true
      row               = 1
      column            = 1
      width             = 3
      height            = 3
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM (FROM K8sPodSample SELECT latest(status) AS estado, latest(isReady) AS pronto WHERE ${local.nrql_operational_pods} FACET podName LIMIT MAX) SELECT filter(count(*), WHERE estado = 'Running' AND pronto = 1) AS 'Pods ativos' SINCE 3 minutes ago"
      }
    }
    widget_billboard {
      title             = "Healthcheck externo (ultimo resultado - 5 min)"
      ignore_time_range = true
      row               = 1
      column            = 4
      width             = 3
      height            = 3
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM SyntheticCheck SELECT latest(result) AS 'Health' WHERE ${local.nrql_operational_synthetic} SINCE 5 minutes ago"
      }
    }
    widget_billboard {
      title  = "Uptime no periodo (%)"
      row    = 1
      column = 7
      width  = 3
      height = 3
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM SyntheticCheck SELECT percentage(count(*), WHERE result = 'SUCCESS') AS 'Disponibilidade (%)' WHERE ${local.nrql_operational_synthetic} SINCE 1 day ago"
      }
    }
    widget_billboard {
      title  = "Falhas no processamento de OS"
      row    = 1
      column = 10
      width  = 3
      height = 3
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM OficinaOsEvent SELECT filter(count(*), WHERE evento = 'FALHA_PROCESSAMENTO') AS 'Falhas' WHERE ${local.nrql_business_events} SINCE 1 day ago"
      }
    }
    widget_line {
      title  = "Latencia p95 (ms)"
      row    = 4
      column = 1
      width  = 6
      height = 3
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM Transaction SELECT percentile(duration * 1000, 95) AS 'p95 (ms)' WHERE ${local.nrql_api_transactions} TIMESERIES"
      }
    }
    widget_line {
      title  = "Throughput por minuto"
      row    = 4
      column = 7
      width  = 6
      height = 3
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM Transaction SELECT rate(count(*), 1 minute) WHERE ${local.nrql_api_transactions} TIMESERIES"
      }
    }
    widget_bar {
      title  = "Erros HTTP por status"
      row    = 7
      column = 1
      width  = 6
      height = 3
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM Transaction SELECT count(*) WHERE ${local.nrql_api_transactions} AND numeric(http.statusCode) >= 400 FACET http.statusCode"
      }
    }
    widget_table {
      title  = "Endpoints mais lentos"
      row    = 7
      column = 7
      width  = 6
      height = 3
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM Transaction SELECT percentile(duration * 1000, 95) AS 'p95 (ms)', average(duration * 1000) AS 'Media (ms)', count(*) AS 'Requisicoes' WHERE ${local.nrql_api_transactions} FACET name LIMIT 20"
      }
    }
    widget_line {
      title  = "CPU por pod - consumo, alvo HPA e limite (cores)"
      row    = 10
      column = 1
      width  = 6
      height = 3
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM K8sContainerSample SELECT average(cpuUsedCores) AS 'Media (cores)', max(cpuUsedCores) AS 'Maximo observado (cores)', latest(cpuRequestedCores) * 0.7 AS 'Alvo HPA 70% (cores)', latest(cpuLimitCores) AS 'Limite provisionado (cores)' WHERE ${local.nrql_operational_containers} AND podName LIKE {{pod}} FACET podName TIMESERIES"
      }
    }
    widget_line {
      title  = "Memoria por pod - consumo e limite (MiB)"
      row    = 10
      column = 7
      width  = 6
      height = 3
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM K8sContainerSample SELECT average(memoryWorkingSetBytes) / 1048576 AS 'Consumo (MiB)', latest(memoryLimitBytes) / 1048576 AS 'Limite provisionado (MiB)' WHERE ${local.nrql_operational_containers} AND podName LIKE {{pod}} FACET podName TIMESERIES"
      }
    }
    widget_bar {
      title  = "Restarts por pod"
      row    = 13
      column = 1
      width  = 6
      height = 3
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM K8sContainerSample SELECT max(restartCount) WHERE ${local.nrql_operational_containers} AND podName LIKE {{pod}} FACET podName LIMIT 20"
      }
    }
    widget_line {
      title  = "Falhas de OS ao longo do tempo"
      row    = 16
      column = 1
      width  = 6
      height = 3
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM OficinaOsEvent SELECT filter(count(*), WHERE evento = 'FALHA_PROCESSAMENTO') AS 'Falhas' WHERE ${local.nrql_business_events} TIMESERIES"
      }
    }
    widget_table {
      title  = "Falhas de OS por fluxo e erro"
      row    = 16
      column = 7
      width  = 6
      height = 3
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM OficinaOsEvent SELECT count(*) AS 'Falhas' WHERE ${local.nrql_business_events} AND evento = 'FALHA_PROCESSAMENTO' FACET fluxo, erro LIMIT 30"
      }
    }
    widget_table {
      title  = "Logs estruturados e correlacao de requisicoes"
      row    = 19
      column = 1
      width  = 12
      height = 5
      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM Log SELECT timestamp AS 'Data/hora', level AS 'Nivel', message AS 'Mensagem', requestMethod AS 'Metodo', requestUri AS 'Rota', statusCode AS 'HTTP', elapsedMs AS 'Duracao (ms)', correlationId AS 'Correlation ID', `trace.id` AS 'Trace ID', pod_name AS 'Pod' WHERE ${local.nrql_operational_logs} AND pod_name LIKE {{pod}} AND level LIKE {{level}} AND ({{correlation}} = '%' OR correlationId LIKE {{correlation}}) SINCE 30 minutes ago LIMIT 100"
      }
    }
  }
}

resource "newrelic_nrql_alert_condition" "external_health" {
  count = local.new_relic_observability_enabled ? 1 : 0

  account_id                     = var.new_relic_account_id
  policy_id                      = newrelic_alert_policy.oficina[0].id
  type                           = "static"
  name                           = "${local.name} - Health externo API"
  description                    = "Duas janelas consecutivas de 1 minuto com falha no readiness publico. Ausencia de sinal por 3 minutos tambem abre incidente."
  enabled                        = true
  violation_time_limit_seconds   = 3600
  aggregation_window             = 60
  aggregation_method             = "event_flow"
  aggregation_delay              = 60
  expiration_duration            = 180
  open_violation_on_expiration   = true
  close_violations_on_expiration = false

  nrql {
    query = "FROM SyntheticCheck SELECT filter(count(*), WHERE result = 'FAILED') WHERE ${local.nrql_operational_synthetic}"
  }
  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 120
    threshold_occurrences = "ALL"
  }
}
