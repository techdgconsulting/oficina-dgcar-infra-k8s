# Operacao Da Infraestrutura Kubernetes E Borda

## Componentes

- VPC e subnets para workloads e banco.
- EKS para execucao da API principal.
- ECR para imagens Docker.
- API Gateway HTTP como entrada oficial.
- Rotas opcionais para API principal e autenticacao por CPF.
- New Relic Kubernetes integration para telemetria operacional do cluster.
- Manifests Kubernetes versionados em `k8s/`.

## API Gateway

O API Gateway e criado por padrao. As integracoes sao ativadas quando as variaveis correspondentes sao informadas:

- `api_backend_url`: habilita proxy para a API principal.
- `auth_lambda_invoke_arn`: habilita rota `POST /auth/cpf`.
- `auth_lambda_function_name`: cria permissao de invocacao da Lambda pelo API Gateway.

## Kubernetes

Os manifests base incluem:

- `namespace.yaml`;
- `configmap.yaml`;
- `secret.example.yaml`;
- `deployment.yaml`;
- `service.yaml`;
- `hpa.yaml`;
- `kustomization.yaml`.

O arquivo `secret.example.yaml` e apenas modelo. Secrets reais devem ser aplicados por pipeline, ferramenta de secrets ou ambiente seguro.

## Ambientes

- `homolog`: deploy automatico a partir da branch `homolog`.
- `prod`: deploy a partir de `main`, protegido por aprovacao no GitHub Environment.

## Observabilidade

A integracao New Relic Kubernetes e instalada pelo Terraform usando o chart oficial `nri-bundle`.

O provisionamento cria o namespace `newrelic` e instala os componentes para monitorar:

- CPU e memoria de nodes, pods e containers;
- pods e restarts;
- eventos Kubernetes;
- workloads e HPA via kube-state-metrics;
- health operacional por readiness/liveness e disponibilidade dos pods.

O secret `NEW_RELIC_LICENSE_KEY` deve existir no GitHub Environment usado pela esteira (`homolog` ou `prod`).

Logs de containers permanecem desabilitados nesta fase para controlar ingestao. A correlacao e os logs JSON da API ficam implementados no repositorio `oficina-dgcar-api`.
