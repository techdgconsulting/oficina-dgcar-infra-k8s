locals {
  nrql_business_period     = "aggregationendtime() AS periodo_fim, aggregationendtime() - round(count(*) / rate(count(*), 1 second) * 1000) AS periodo_inicio"
  nrql_business_completion = "FROM OficinaOsOperationalSnapshot SELECT latest(status) AS status, latest(mecanico_nome) AS mecanico, latest(data_finalizacao_ms) AS finalizada_em, ${local.nrql_business_period} WHERE app_name = '${local.new_relic_app_name}' AND snapshot_version = 2 FACET numero_os LIMIT MAX"
  nrql_business_durations  = "FROM OficinaOsStatusDurationSnapshot SELECT latest(tempo_ms) AS tempo_ms, latest(fim_ms) AS fim_ms, ${local.nrql_business_period} WHERE app_name = '${local.new_relic_app_name}' FACET numero_os, status, inicio_ms LIMIT MAX"
  nrql_business_events     = "app_name = '${local.new_relic_app_name}'"
  nrql_business_latest     = "FROM OficinaOsOperationalSnapshot SELECT latest(status) AS status, latest(cliente_nome) AS cliente, latest(veiculo) AS veiculo, latest(placa) AS placa, latest(mecanico_nome) AS mecanico, latest(valor_total) AS valor, latest(data_entrega) AS entrega, latest(finalizada_hoje) AS finalizada_hoje WHERE app_name = '${local.new_relic_app_name}' AND snapshot_version = 2 FACET numero_os LIMIT MAX"
  nrql_api_transactions    = "appName = '${local.new_relic_app_name}'"
  nrql_k8s_cluster         = "clusterName = '${local.new_relic_cluster_name}'"
  nrql_k8s_app             = "clusterName = '${local.new_relic_cluster_name}' AND namespaceName = '${local.new_relic_namespace_app}'"
}

resource "newrelic_one_dashboard" "business" {
  count = local.new_relic_observability_enabled ? 1 : 0

  name        = "${local.name} - Negocio OS"
  permissions = "public_read_only"

  page {
    name = "Ordens de Servico"

    widget_billboard {
      title  = "Total de OS em aberto"
      row    = 1
      column = 1
      width  = 3
      height = 4

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM (${local.nrql_business_latest}) SELECT count(*) AS 'OS' WHERE status NOT IN ('ENTREGUE', 'CANCELADA') SINCE 30 minutes ago"
      }
    }

    widget_bar {
      title  = "Status das OS"
      row    = 1
      column = 4
      width  = 9
      height = 4

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM (${local.nrql_business_latest}) SELECT count(*) AS 'OS' FACET status SINCE 30 minutes ago LIMIT MAX"
      }
    }

    widget_table {
      title  = "Ordens de servico"
      row    = 5
      column = 1
      width  = 12
      height = 4

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM (${local.nrql_business_latest}) SELECT latest(cliente) AS 'Cliente', latest(veiculo) AS 'Veiculo', latest(placa) AS 'Placa', latest(mecanico) AS 'Mecanico', latest(status) AS 'Status', latest(entrega) AS 'Data de entrega', latest(valor) AS 'Valor' WHERE status != 'CANCELADA' FACET numero_os AS 'OS' SINCE 30 minutes ago LIMIT 100"
      }
    }

    widget_bar {
      title  = "Volume diario de ordens de servico"
      row    = 9
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM OficinaOsOperationalSnapshot SELECT uniqueCount(numero_os) AS 'OS criadas' WHERE ${local.nrql_business_events} AND snapshot_version = 2 AND dias_desde_criacao >= 0 AND dias_desde_criacao < 14 FACET data_criacao_dia SINCE 30 minutes ago LIMIT 14"
      }
    }

    widget_bar {
      title  = "Produtividade por mecanico"
      row    = 9
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM (${local.nrql_business_completion}) SELECT count(*) AS 'OS finalizadas' WHERE status IN ('FINALIZADA', 'AGUARDANDO_RETIRADA', 'ENTREGUE') AND mecanico NOT IN ('NAO_ATRIBUIDO', 'NAO_INFORMADO') AND finalizada_em >= periodo_inicio AND finalizada_em < periodo_fim FACET mecanico SINCE 1 day ago WITH TIMEZONE 'America/Sao_Paulo' LIMIT MAX"
      }
    }

    widget_table {
      title  = "Tempo medio de execucao por status"
      row    = 12
      column = 1
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM (${local.nrql_business_durations}) SELECT average(tempo_ms) / 60000 AS 'Minutos' WHERE fim_ms >= periodo_inicio AND fim_ms < periodo_fim AND status IN ('EM_DIAGNOSTICO', 'EM_EXECUCAO', 'FINALIZADA') FACET status SINCE 1 day ago WITH TIMEZONE 'America/Sao_Paulo' LIMIT MAX"
      }
    }

    widget_table {
      title  = "Erros e falhas nas integracoes"
      row    = 12
      column = 7
      width  = 6
      height = 3

      nrql_query {
        account_id = var.new_relic_account_id
        query      = "FROM OficinaOsEvent SELECT count(*) AS 'Ocorrencias' WHERE ${local.nrql_business_events} AND evento IN ('FALHA_PROCESSAMENTO', 'FALHA_NOTIFICACAO', 'FALHA_PAGAMENTO') FACET evento, erro SINCE 1 day ago WITH TIMEZONE 'America/Sao_Paulo'"
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
    query = "FROM K8sContainerSample SELECT count(*) WHERE ${local.nrql_k8s_app} AND containerName = 'oficina-api' AND isReady = 0"
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
  # Sparse failure events: evaluate empty windows as zero so recovery can close.
  aggregation_method = "cadence"
  aggregation_window = 60
  aggregation_delay  = 60
  fill_option        = "static"
  fill_value         = 0

  nrql {
    query = "FROM OficinaOsEvent SELECT count(*) WHERE ${local.nrql_business_events} AND evento = 'FALHA_PROCESSAMENTO'"
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
