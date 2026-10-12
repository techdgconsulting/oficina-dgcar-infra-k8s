# oficina-dgcar-infra-k8s

Infraestrutura Kubernetes, registry, API Gateway e automacao operacional dos ambientes `homolog` e `prod` da Oficina Mecanica DGCar.

## Proposito

Este repositorio provisiona a base de execucao da solucao na AWS e coordena a integracao dos demais repositorios tecnicos.

Responsabilidades principais:

- provisionar VPC, subnets, route tables e internet gateway;
- provisionar security groups compartilhados;
- provisionar Amazon EKS e node group;
- provisionar Amazon ECR;
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
3. publica outputs de rede para banco, Lambda e API;
4. dispara provisionamento do RDS;
5. dispara provisionamento da Lambda;
6. reexecuta banco para liberar acesso da Lambda;
7. publica codigo da Lambda;
8. integra `POST /auth/cpf` no API Gateway;
9. publica `OFICINA_PUBLIC_BASE_URL` no repo da API;
10. publica a API no EKS;
11. integra `ANY /{proxy+}` no API Gateway;
12. valida outputs finais e smoke tests quando solicitado.

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
- `GH_ACTIONS_IAM_USER_NAME`.

Variables esperadas:

- `AWS_REGION`.

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
