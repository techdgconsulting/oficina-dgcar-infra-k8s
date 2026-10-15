# Dashboard API e Kubernetes

O dashboard de negocio e independente e nao e modificado por esta publicacao.

## Indicadores

- Pods ativos: ultimo estado por pod, Running e Ready, com amostra nos ultimos 3 minutos. Usa janela fixa, sem contar pods de rollouts antigos pelo historico do periodo escolhido.
- Health externo: ultimo resultado SUCCESS/FAILED do readiness publico pelo API Gateway, janela fixa de 5 minutos. Sem amostras significa ausencia de telemetria.
- Uptime: percentual de SyntheticCheck com resultado SUCCESS no periodo selecionado. Nao representa disponibilidade anterior a criacao do monitor.
- APIs: p95 e media em milissegundos, throughput por minuto e erros HTTP por codigo.
- CPU e memoria: consumo do container oficina-api por pod e limite real do mesmo container. CPU em cores, memoria em MiB. A linha de limite nao usa requests nem numeros fixos. Se o limite nao existir na telemetria, a linha fica ausente; isso nao indica limite zero.
- Restarts por pod preservados. Nao ha grafico de HPA nem card de pods desejados.
- Falhas de OS: evento FALHA_PROCESSAMENTO, filtrado por app_name do ambiente.
- Logs: data/hora, nivel, mensagem, metodo, rota, HTTP, duracao, correlationId, trace.id e pod.

Filtros de pod, nivel e correlationId aceitam `%` para todos. Pod filtra recursos e logs; os outros dois filtros se aplicam aos logs. O seletor de periodo controla historico e uptime, mas nao altera os cards de estado atual.

## Logs JSON

API stdout JSON -> New Relic Kubernetes logging -> New Relic Logs.

O coletor le somente `/var/log/containers/oficina-api-*_oficina_oficina-api-*.log`, interpreta o JSON e preserva MDC, stacktrace e metadados do Kubernetes. O provider Logback adiciona os metadados do agente New Relic como campos JSON. Fora de uma transacao trace.id/span.id podem estar ausentes.

O encaminhamento automatico do agente Java e a decoracao textual estao desabilitados no deploy: o coletor e o unico caminho. O correlationId recebido ou gerado pelo filtro HTTP tambem e atributo da Transaction APM. Duas requisicoes com o mesmo X-Correlation-Id podem ser pesquisadas juntas, mantendo trace.id distintos. Nao e uma garantia de propagacao para integracoes externas que ainda nao a implementam.

No New Relic Logs, filtrar `correlationId = 'valor'` ou `trace.id = 'valor'`, inspecionar o JSON e abrir o trace associado. Nao sao registrados bodies ou headers de autorizacao pelo filtro HTTP. A retencao e o volume permitido dependem da conta; a coleta esta restrita a API para evitar ingestao de logs do cluster inteiro.

## Alertas e disponibilidade

O monitor SIMPLE chama `/actuator/health/readiness` no API Gateway a cada minuto, de US_EAST_1, verificando HTTP e o texto `"status":"UP"`.

O alerta externo abre apos duas janelas consecutivas de um minuto com falha. Ausencia de sinal por tres minutos tambem abre incidente. Latencia de agregacao, envio e recuperacao deve ser considerada; nao e garantia de notificacao exatamente em dois minutos.

O alerta preexistente de falha de processamento preserva seu limite e duracao, agora isolando app_name. Alertas de 5xx, latencia, readiness de containers e restarts sao preservados. Incidentes ficam no New Relic; nenhum destinatario externo e criado sem definicao do usuario.

## Publicacao e verificacao

1. API: executar Maven/CI e publicar o provider JSON e a configuracao de logging.
2. Infra: executar CI, fmt, validate e testes de protecao de escopo.
3. Workflow `Atualizar Dashboard Operacional Homolog`, fase `deploy`: plano limitado ao dashboard novo, coletor, monitor e alertas relacionados. Valida escopo e compila as 14 consultas reais via NerdGraph antes de aplicar.
4. Verificacao ao vivo: pods ativos contra Kubernetes; limites das duas linhas contra resources.limits; SyntheticCheck com sucesso; duas requisicoes GET com mesmo correlationId, dois traces, campos JSON, correspondencia nas transactions APM e ausencia de duplicacao.
5. Fase `retire`: somente apos a verificacao anterior passar, remover os dashboards API e Kubernetes antigos. Plano protegido permite apenas essas duas exclusoes. Os outputs antigos passam a apontar para o unificado.
6. Fase `verify`: repetir verificacao sem apply.

Planos completos em provisionamentos futuros tambem convergem para o dashboard unificado. A publicacao direcionada nao altera rede, EKS, banco ou massa de negocio.
