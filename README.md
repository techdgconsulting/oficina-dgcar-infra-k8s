# oficina-dgcar-infra-k8s

Infraestrutura Kubernetes, registry, API Gateway e automacao operacional dos ambientes `homolog` e `prod` da Oficina Mecanica DGCar.

## Proposito

Este repositorio provisiona a base de execucao da solucao na AWS e coordena a integracao dos demais repositorios tecnicos.

Responsabilidades principais:

- provisionar VPC, subnets, route tables e internet gateway;
- provisionar security groups compartilhados;
- provisionar Amazon EKS e node group;
- provisionar Amazon ECR;
- instalar New Relic Kubernetes no EKS;
- provisionar API Gateway HTTP como entrada oficial da solucao;
- integrar `POST /auth/cpf` com a Lambda Auth CPF + Senha;
- integrar `ANY /{proxy+}` com a API Spring Boot executando no EKS;
- manter manifests Kubernetes, Kustomize, Deployment, Service e HPA;
- publicar outputs consumidos por API, banco e Lambda;
- orquestrar provisionamento e destroy dos ambientes academicos.

## Tecnologias

- Terraform;
- AWS VPC;
- AWS EKS;
- AWS ECR;
- AWS API Gateway HTTP API;
- Kubernetes;
- Kustomize;
- Helm;
- New Relic;
- GitHub Actions;
- Bash;
- kubectl.

## Diagrama Da Arquitetura Do Repositorio

```mermaid
flowchart LR
  users[Usuarios externos e internos] --> gateway[API Gateway HTTP]
  gateway --> authRoute[POST /auth/cpf]
  gateway --> proxyRoute[ANY /{proxy+}]
  authRoute --> lambda[oficina-dgcar-auth-lambda]
  proxyRoute --> svc[Kubernetes Service<br/>oficina-api]
  svc --> pod[Pods Spring Boot<br/>oficina-dgcar-api]
  pod --> rds[(RDS PostgreSQL)]
  lambda --> rds
  gha[GitHub Actions] --> terraform[Terraform]
  terraform --> eks[EKS, ECR, VPC e Gateway]
  terraform --> nr[New Relic Kubernetes]
```

Este repositorio cria a infraestrutura de borda e execucao. O banco fica no `oficina-dgcar-infra-db`, a autenticacao externa fica no `oficina-dgcar-auth-lambda` e a aplicacao fica no `oficina-dgcar-api`.

## Repositorios Integrados

- `oficina-dgcar-api`: publica imagem Docker no ECR, aplica manifests no EKS e expoe o Service da aplicacao.
- `oficina-dgcar-auth-lambda`: cria a Lambda Auth CPF + Senha e publica dados para integracao com o API Gateway.
- `oficina-dgcar-infra-db`: cria o RDS PostgreSQL e libera conectividade para API e Lambda.
- `oficina-dgcar-docs`: centraliza documentacao arquitetural, ADRs, RFCs, diagramas e modelo de dados.

## Execucao Local

Validacao Terraform:

```bash
cd terraform
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

Validacao dos scripts:

```bash
bash -n scripts/preflight/*.sh scripts/github-actions/*.sh scripts/aws/*.sh scripts/smoke/*.sh
```

Validacao dos manifests Kubernetes:

```bash
kubectl kustomize k8s > rendered-k8s.yaml
test -s rendered-k8s.yaml
```

## Deploy E Provisionamento

Fluxo oficial de promocao:

```text
feature/* -> PR -> homolog
homolog -> deploy automatico homolog

homolog -> PR -> main
main -> deploy automatico prod
```

Workflows principais:

| Workflow | Ambiente | Finalidade |
|---|---|---|
| `.github/workflows/provision-homolog.yml` | `homolog` | Provisiona VPC, EKS, ECR, API Gateway e integra os repos dependentes. |
| `.github/workflows/destroy-homolog.yml` | `homolog` | Remove workloads, Gateway, Lambda, RDS, EKS, ECR e rede na ordem segura. |
| `.github/workflows/provision-prod.yml` | `prod` | Provisiona producao a partir de merge em `main` e GitHub Environment `prod`. |
| `.github/workflows/destroy-prod.yml` | `prod` | Remove producao com aprovacao e protecoes do environment `prod`. |

O provisionamento completo executa:

1. valida credenciais, GitHub token, state remoto e locks;
2. cria rede, EKS, node group, ECR e API Gateway;
3. instala New Relic Kubernetes no EKS;
4. publica outputs de rede para banco, Lambda e API;
5. dispara provisionamento do RDS;
6. dispara provisionamento da Lambda;
7. reexecuta banco para liberar acesso da Lambda;
8. publica codigo da Lambda;
9. integra `POST /auth/cpf` no API Gateway;
10. publica `OFICINA_PUBLIC_BASE_URL` no repo da API;
11. publica a API no EKS;
12. integra `ANY /{proxy+}` no API Gateway;
13. valida outputs finais e smoke tests quando solicitado.

`workflow_dispatch` permanece disponivel para reprocessamento operacional controlado. Producao usa GitHub Environment `prod` e pode exigir aprovacao antes do deploy.

## Operacao Do Ambiente

A operacao ponta a ponta do ambiente fica registrada neste README para evitar documento operacional duplicado. As secoes principais sao:

- `Deploy E Provisionamento`: fluxo de promocao, workflows e ordem de provisionamento.
- `Secrets E Variables`: configuracao esperada nos GitHub Environments.
- `Outputs Publicados`: valores compartilhados com API, banco e Lambda.
- `Swagger E Postman`: links de validacao funcional via API Gateway.
- `Branches E Ambientes`: regra `feature/* -> homolog -> main` e deploy automatico.

## Secrets E Variables

Secrets esperados nos environments `homolog` e `prod`:

- `AWS_ACCESS_KEY_ID`;
- `AWS_SECRET_ACCESS_KEY`;
- `GH_AUTOMATION_TOKEN`;
- `TF_STATE_BUCKET`;
- `TF_STATE_KEY`;
- `GH_ACTIONS_IAM_USER_ARN`;
- `GH_ACTIONS_IAM_USER_NAME`;
- `NEW_RELIC_LICENSE_KEY`;
- `NEW_RELIC_API_KEY`.

Variables esperadas:

- `AWS_REGION`;
- `NEW_RELIC_ACCOUNT_ID`.

Smoke tests usam:

- `CLIENT_TEST_CPF`;
- `CLIENT_TEST_PASSWORD`;
- `CLIENT_TEST_OS_NUMBER`;
- `CLIENT_OTHER_OS_NUMBER`.

## Outputs Publicados

Este repositorio publica outputs usados pelos demais repositorios:

- `VPC_ID`;
- `PRIVATE_SUBNET_IDS`;
- `ALLOWED_DB_SECURITY_GROUP_IDS`;
- `ECR_REPOSITORY`;
- `EKS_CLUSTER_NAME`;
- endpoint publico do API Gateway, publicado para a API como `OFICINA_PUBLIC_BASE_URL`.

Outputs Terraform usados como evidencia da observabilidade:

- `new_relic_kubernetes_enabled`;
- `new_relic_kubernetes_namespace`;
- `new_relic_kubernetes_release`;
- `new_relic_observability_enabled`;
- `new_relic_dashboard_api_guid`;
- `new_relic_dashboard_kubernetes_guid`;
- `new_relic_dashboard_business_guid`;
- `new_relic_alert_policy_id`.

## Observabilidade Kubernetes

O Terraform instala o chart oficial `nri-bundle` no namespace `newrelic`.

A integracao cobre:

- CPU e memoria de nodes, pods e containers;
- pods e restarts;
- eventos Kubernetes;
- workloads e HPA via kube-state-metrics;
- health operacional por readiness/liveness e disponibilidade dos pods.

Logs de containers ficam desabilitados nesta fase para controlar ingestao. A API ja envia telemetria APM pelo Java Agent no repositorio `oficina-dgcar-api`.

## Dashboards E Alertas

O Terraform cria dashboards e alertas no New Relic usando a `NEW_RELIC_API_KEY`.

Dashboards criados por ambiente:

- `${project_name}-${environment} - API`: latencia, throughput, erros HTTP e endpoints lentos;
- `${project_name}-${environment} - Kubernetes`: CPU, memoria, pods, restarts e HPA;
- `${project_name}-${environment} - Negocio OS`: volume diario de OS, tempo medio por status e falhas de OS, email e pagamento.

Alertas criados por ambiente:

- API 5xx;
- API p95 alto;
- health down por containers nao prontos;
- pod reiniciando;
- falha no processamento de OS;
- falha de notificacao;
- falha de pagamento.

Validacao visual:

```text
New Relic -> Kubernetes
New Relic -> All Entities -> oficina-dgcar-homolog-eks ou oficina-dgcar-prod-eks
New Relic -> Dashboards -> oficina-dgcar-homolog - API/Kubernetes/Negocio OS
New Relic -> Alerts -> Alert policies -> oficina-dgcar-homolog - Observabilidade
```

## Swagger E Postman

Este repositorio nao possui API propria, mas provisiona o API Gateway que expoe a API e a Lambda.

Links operacionais de homologacao:

- Swagger UI da API via Gateway: `${OFICINA_PUBLIC_BASE_URL}/swagger-ui.html`
- OpenAPI JSON via Gateway: `${OFICINA_PUBLIC_BASE_URL}/api-docs`
- Autenticacao externa: `${OFICINA_PUBLIC_BASE_URL}/auth/cpf`
- Collection Postman: [`oficina-dgcar-api/postman/Oficina-DGCar-Tech-Challenge-Fase-3.postman_collection.json`](https://github.com/techdgconsulting/oficina-dgcar-api/blob/homolog/postman/Oficina-DGCar-Tech-Challenge-Fase-3.postman_collection.json)

O valor de `OFICINA_PUBLIC_BASE_URL` deve ser obtido apos cada provisionamento. Nao usar IDs fixos de API Gateway na documentacao, pois eles podem mudar apos destroy e nova subida do ambiente.

## Branches E Ambientes

- `homolog`: branch de homologacao, protegida contra commits diretos; recebe PRs de `feature/*` e dispara deploy automatico no environment `homolog`.
- `main`: branch de producao, protegida contra commits diretos; recebe PRs vindos de `homolog` e dispara deploy automatico no environment `prod`.
- Pull Requests sao o caminho obrigatorio de merge.
- GitHub Environments `homolog` e `prod` concentram secrets, variables e aprovacoes.

## Documentacao Central

A documentacao arquitetural completa esta centralizada em:

[oficina-dgcar-docs](https://github.com/techdgconsulting/oficina-dgcar-docs)

Este repositorio mantem apenas a documentacao operacional da infraestrutura Kubernetes, API Gateway e automacao dos ambientes.

## Origem Historica

O commit de origem e a rastreabilidade da extracao estao registrados em [`ORIGEM_HISTORICA.md`](./ORIGEM_HISTORICA.md).
