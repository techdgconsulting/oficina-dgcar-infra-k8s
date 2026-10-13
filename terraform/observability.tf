locals {
  nrql_api_transactions = "appName = '${local.new_relic_app_name}'"
  nrql_k8s_cluster      = "clusterName = '${local.new_relic_cluster_name}'"
  nrql_k8s_app          = "clusterName = '${local.new_relic_cluster_name}' AND namespaceName = '${local.new_relic_namespace_app}'"
}

resource "newrelic_one_dashboard" "api" {
  count = local.new_relic_observability_enabled ? 1 : 0

  name        = "${local.name} - API"
  permissions = "public_read_only"

  page {
    name = "API"

    widget_line {
      title  = "Latencia p95"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM Transaction SELECT percentile(duration, 95) WHERE ${local.nrql_api_transactions} TIMESERIES"
      }
    }

    widget_line {
      title  = "Throughput por minuto"
      row    = 1
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
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM Transaction SELECT count(*) WHERE ${local.nrql_api_transactions} AND http.statusCode >= 400 FACET http.statusCode"
      }
    }

    widget_table {
      title  = "Endpoints mais lentos"
      row    = 4
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM Transaction SELECT percentile(duration, 95), average(duration), count(*) WHERE ${local.nrql_api_transactions} FACET name LIMIT 20"
      }
    }
  }
}

resource "newrelic_one_dashboard" "kubernetes" {
  count = local.new_relic_observability_enabled ? 1 : 0

  name        = "${local.name} - Kubernetes"
  permissions = "public_read_only"

  page {
    name = "Kubernetes"

    widget_line {
      title  = "CPU por pod"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM K8sContainerSample SELECT average(cpuUsedCores) WHERE ${local.nrql_k8s_app} FACET podName TIMESERIES"
      }
    }

    widget_line {
      title  = "Memoria por pod"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM K8sContainerSample SELECT average(memoryWorkingSetBytes) WHERE ${local.nrql_k8s_app} FACET podName TIMESERIES"
      }
    }

    widget_billboard {
      title  = "Pods em execucao"
      row    = 4
      column = 1
      width  = 3
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM K8sPodSample SELECT uniqueCount(podName) WHERE ${local.nrql_k8s_app} AND status = 'Running'"
      }
    }

    widget_bar {
      title  = "Restarts por pod"
      row    = 4
      column = 4
      width  = 5
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM K8sContainerSample SELECT max(restartCount) WHERE ${local.nrql_k8s_app} FACET podName LIMIT 20"
      }
    }

    widget_line {
      title  = "HPA replicas atuais x desejadas"
      row    = 4
      column = 9
      width  = 4
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM K8sHpaSample SELECT latest(currentReplicas), latest(desiredReplicas), latest(maxReplicas) WHERE ${local.nrql_k8s_app} FACET hpaName TIMESERIES"
      }
    }
  }
}

resource "newrelic_one_dashboard" "business" {
  count = local.new_relic_observability_enabled ? 1 : 0

  name        = "${local.name} - Negocio OS"
  permissions = "public_read_only"

  page {
    name = "Ordens de Servico"

    widget_bar {
      title  = "Volume diario de OS"
      row    = 1
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM OficinaOsEvent SELECT count(*) WHERE evento = 'OS_CRIADA' FACET status TIMESERIES"
      }
    }

    widget_bar {
      title  = "Mudancas de status"
      row    = 1
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM OficinaOsEvent SELECT count(*) WHERE evento = 'STATUS_ALTERADO' FACET status_atual TIMESERIES"
      }
    }

    widget_table {
      title  = "Tempo medio por status"
      row    = 4
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM OficinaOsEvent SELECT average(tempo_ms) WHERE evento = 'TEMPO_STATUS' AND status IN ('EM_DIAGNOSTICO', 'EM_EXECUCAO', 'FINALIZADA') FACET status"
      }
    }

    widget_billboard {
      title  = "Falhas de OS"
      row    = 4
      column = 7
      width  = 2
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM OficinaOsEvent SELECT count(*) WHERE evento = 'FALHA_PROCESSAMENTO'"
      }
    }

    widget_billboard {
      title  = "Falhas de email"
      row    = 4
      column = 9
      width  = 2
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM OficinaOsEvent SELECT count(*) WHERE evento = 'FALHA_NOTIFICACAO'"
      }
    }

    widget_billboard {
      title  = "Falhas de pagamento"
      row    = 4
      column = 11
      width  = 2
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM OficinaOsEvent SELECT count(*) WHERE evento = 'FALHA_PAGAMENTO'"
      }
    }
  }
}

resource "newrelic_alert_policy" "oficina" {
  count = local.new_relic_observability_enabled ? 1 : 0

  name                = "${local.name} - Observabilidade"
  incident_preference = "PER_CONDITION"
}

resource "newrelic_nrql_alert_condition" "api_5xx" {
  count = local.new_relic_observability_enabled ? 1 : 0

  account_id                   = var.new_relic_account_id
  policy_id                    = newrelic_alert_policy.oficina[0].id
  type                         = "static"
  name                         = "${local.name} - API 5xx"
  description                  = "Alerta quando a API registra respostas HTTP 5xx."
  enabled                      = true
  violation_time_limit_seconds = 3600

  nrql {
    query = "FROM Transaction SELECT count(*) WHERE ${local.nrql_api_transactions} AND http.statusCode >= 500"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 300
    threshold_occurrences = "AT_LEAST_ONCE"
  }
}

resource "newrelic_nrql_alert_condition" "api_p95_high" {
  count = local.new_relic_observability_enabled ? 1 : 0

  account_id                   = var.new_relic_account_id
  policy_id                    = newrelic_alert_policy.oficina[0].id
  type                         = "static"
  name                         = "${local.name} - API p95 alto"
  description                  = "Alerta quando a latencia p95 da API fica acima do limite definido."
  enabled                      = true
  violation_time_limit_seconds = 3600

  nrql {
    query = "FROM Transaction SELECT percentile(duration, 95) WHERE ${local.nrql_api_transactions}"
  }

  critical {
    operator              = "above"
    threshold             = var.new_relic_alert_p95_threshold_seconds
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }
}

resource "newrelic_nrql_alert_condition" "health_down" {
  count = local.new_relic_observability_enabled ? 1 : 0

  account_id                   = var.new_relic_account_id
  policy_id                    = newrelic_alert_policy.oficina[0].id
  type                         = "static"
  name                         = "${local.name} - Health down"
  description                  = "Alerta quando containers da API deixam de ficar prontos no Kubernetes."
  enabled                      = true
  violation_time_limit_seconds = 3600

  nrql {
    query = "FROM K8sContainerSample SELECT count(*) WHERE ${local.nrql_k8s_app} AND isReady = false"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 300
    threshold_occurrences = "AT_LEAST_ONCE"
  }
}

resource "newrelic_nrql_alert_condition" "pod_restart" {
  count = local.new_relic_observability_enabled ? 1 : 0

  account_id                   = var.new_relic_account_id
  policy_id                    = newrelic_alert_policy.oficina[0].id
  type                         = "static"
  name                         = "${local.name} - Pod reiniciando"
  description                  = "Alerta quando ha incremento de restarts dos containers da aplicacao."
  enabled                      = true
  violation_time_limit_seconds = 3600

  nrql {
    query = "FROM K8sContainerSample SELECT sum(restartCountDelta) WHERE ${local.nrql_k8s_app}"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 300
    threshold_occurrences = "AT_LEAST_ONCE"
  }
}

resource "newrelic_nrql_alert_condition" "os_processing_failure" {
  count = local.new_relic_observability_enabled ? 1 : 0

  account_id                   = var.new_relic_account_id
  policy_id                    = newrelic_alert_policy.oficina[0].id
  type                         = "static"
  name                         = "${local.name} - Falha processamento OS"
  description                  = "Alerta quando a API registra falha no processamento de ordens de servico."
  enabled                      = true
  violation_time_limit_seconds = 3600

  nrql {
    query = "FROM OficinaOsEvent SELECT count(*) WHERE evento = 'FALHA_PROCESSAMENTO'"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 300
    threshold_occurrences = "AT_LEAST_ONCE"
  }
}

resource "newrelic_nrql_alert_condition" "notification_failure" {
  count = local.new_relic_observability_enabled ? 1 : 0

  account_id                   = var.new_relic_account_id
  policy_id                    = newrelic_alert_policy.oficina[0].id
  type                         = "static"
  name                         = "${local.name} - Falha notificacao"
  description                  = "Alerta quando a API registra falha de notificacao por email."
  enabled                      = true
  violation_time_limit_seconds = 3600

  nrql {
    query = "FROM OficinaOsEvent SELECT count(*) WHERE evento = 'FALHA_NOTIFICACAO'"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 300
    threshold_occurrences = "AT_LEAST_ONCE"
  }
}

resource "newrelic_nrql_alert_condition" "payment_failure" {
  count = local.new_relic_observability_enabled ? 1 : 0

  account_id                   = var.new_relic_account_id
  policy_id                    = newrelic_alert_policy.oficina[0].id
  type                         = "static"
  name                         = "${local.name} - Falha pagamento"
  description                  = "Alerta quando a API registra falha de pagamento ou integracao com gateway."
  enabled                      = true
  violation_time_limit_seconds = 3600

  nrql {
    query = "FROM OficinaOsEvent SELECT count(*) WHERE evento = 'FALHA_PAGAMENTO'"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 300
    threshold_occurrences = "AT_LEAST_ONCE"
  }
}
