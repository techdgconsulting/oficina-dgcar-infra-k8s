# Validacao do HPA: 1 -> 2 pods Ready -> 1

## Configuracao

O HPA continua com CPU alvo de 70% do request da API (250m), minReplicas=1 e maxReplicas=3. A carga precisa elevar a utilizacao sustentada para o controlador recomendar mais replicas. O limite de CPU da API permanece 500m; request/limite de memoria permanecem 512Mi/768Mi.

O Metrics Server fornece `metrics.k8s.io` ao HPA. O New Relic continua responsavel pelos dashboards, logs e alertas.

No EC2 existente, o VPC CNI passa a usar prefix delegation. Um Job de configuracao unica instala somente `99-oficina-pod-capacity.conf` no diretorio de drop-ins do kubelet AL2023, com maxPods=17. Reinicia o kubelet sem substituir a instancia. Nao altera kubeReserved, autenticacao, tipo EC2, quantidade de nos ou limites da API. maxPods e um teto de pods do no, nao uma promessa de capacidade para 17 replicas da aplicacao: CPU e memoria continuam limitando o agendamento.

O Job usa hostNetwork/hostPID e privilegio de manutencao apenas para escrever esse drop-in e reiniciar o kubelet. Nao recebe token Kubernetes. O script verifica suporte a drop-in antes de escrever e restaura o arquivo anterior em caso de erro. A configuracao fica persistida no disco do no. Um provisionamento completo recria o Job junto com o cluster; o preflight detecta capacidade insuficiente em um eventual no substituido.

As quatro reservas dos agentes NRK8s (scraper/forwarder KSM, scraper/agent kubelet) passam de 100m/150M para 25m/32Mi por container. O levantamento de homolog mediu 12-21 MiB e menos de 10m por container. Os limites dos agentes e toda a coleta existente sao preservados. O Metrics Server usa uma replica, request 25m/32Mi e limite 200m/128Mi.

## Execucao

Workflow **Validar Escala HPA Homolog**:

- `configure-and-test`: pausa a API, configura o suporte, restaura a API e executa o teste. Ha indisponibilidade temporaria durante a configuracao.
- `test-only`: repete somente o teste de carga, sem configurar o no ou reiniciar a API.

O plano bloqueia qualquer alteracao de EC2, node group, rede Terraform e dashboards. No CNI, caso todos os slots de IP secundarios antigos estejam ocupados, o script pode liberar somente um IP nao primario dos pods da API previamente pausados, depois de confirmar que nenhum pod ativo o utiliza. Isso permite alocar o prefixo sem criar outro EC2.

## Criterios de aprovacao

1. API de metricas disponivel; ScalingActive=True, CPU numerica e uma replica Ready antes da carga.
2. Preflight comprova que o segundo pod cabe em CPU, memoria e quantidade de pods do mesmo no.
3. k6 autentica uma vez e consulta OS existentes com rampa de 5, 10, 20 e 40 usuarios simultaneos. Nao cria nem altera OS.
4. Durante o ensaio, somente maxReplicas e limitado temporariamente a 2. O teste nao executa scale no Deployment. O proprio HPA deve aumentar a quantidade de pods.
5. Dois pods Ready e desiredReplicas=2 por tres amostras consecutivas. UID e providerID do no comprovam que e o mesmo EC2. Nao pode haver restart da API ou MemoryPressure no no; erros HTTP abaixo de 1%.
6. A carga e encerrada e o HPA deve voltar a uma replica Ready sem scale manual. A estabilizacao padrao de scale-down e de aproximadamente cinco minutos.
7. A configuracao original do HPA e restaurada, inclusive em caso de falha. A verificacao New Relic confirma metricas, limites, health externo e logs correlacionados.

O artefato `hpa-scaling-evidence` contem a linha do tempo em `scaling.json`, o resumo de carga e a saida do k6. Os logs nao incluem tokens nem o conteudo das OS.

Os dashboards nao recebem novos widgets. A escala pode ser observada no card existente de pods ativos e nas series de CPU/memoria por pod.
