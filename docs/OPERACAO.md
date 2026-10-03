# Operacao Da Infraestrutura Kubernetes E Borda

## Componentes

- VPC e subnets para workloads e banco.
- EKS para execucao da API principal.
- ECR para imagens Docker.
- API Gateway HTTP como entrada oficial.
- Rotas opcionais para API principal e autenticacao por CPF.
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

A integracao New Relic deve ser adicionada neste repositorio quando a instrumentacao Kubernetes for ativada, pois este repositorio e responsavel pelo cluster e pelos manifests operacionais.
