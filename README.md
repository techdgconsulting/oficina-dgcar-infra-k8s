# oficina-dgcar-infra-k8s

Infraestrutura Kubernetes, registry, API Gateway e automacao operacional do ambiente academico da Oficina Mecanica DGCar.

## Proposito

Este repositorio concentra as esteiras oficiais de criacao e remocao dos ambientes AWS `homolog` e `prod`.

O provisionamento e o destroy nascem aqui. O repositorio de documentacao registra arquitetura e decisoes, mas nao executa infraestrutura.

## Recursos Provisionados

O fluxo de infraestrutura cria e integra obrigatoriamente:

- VPC, subnets, route tables e internet gateway;
- security groups compartilhados;
- Amazon EKS;
- node group;
- New Relic Kubernetes integration via Helm;
- Amazon ECR;
- API Gateway HTTP;
- rota `POST /auth/cpf`;
- integracao API Gateway -> Lambda Auth CPF + senha;
- rota proxy `ANY /{proxy+}`;
- integracao API Gateway -> aplicacao no EKS;
- permissoes para GitHub Actions operar o EKS;
- outputs consumidos pelos repositorios dependentes.

O ambiente so fica concluido quando rede, banco, Lambda, codigo da Lambda, API Gateway, aplicacao no EKS e rotas do Gateway estao funcionando em conjunto.

## Repositorios Integrados

`oficina-dgcar-infra-k8s` coordena a execucao ponta a ponta.

`oficina-dgcar-infra-db` cria o RDS PostgreSQL, subnet group, security group do banco e outputs de conexao.

`oficina-dgcar-auth-lambda` cria a Lambda Auth CPF + senha, IAM, security group, Log Group e publica o pacote da funcao.

`oficina-dgcar-api` cria a imagem Docker, publica no ECR, aplica manifests no EKS e expoe o Service da aplicacao.

## Workflows Oficiais

### Provisionar Ambiente Homolog

Workflow:

```text
.github/workflows/provision-homolog.yml
```

Execucao:

```text
Actions -> Provisionar Ambiente Homolog -> Run workflow
confirm=PROVISIONAR
run_smoke_tests=false ou true
```

O workflow executa:

1. valida confirmacao textual;
2. valida credenciais, token GitHub, state remoto e lock;
3. valida recursos residuais conflitantes;
4. cria rede, EKS, node group, ECR e API Gateway;
5. instala a integracao New Relic Kubernetes no EKS;
6. publica outputs de rede para banco, Lambda e API;
7. executa o provisionamento do banco;
8. executa o provisionamento da Lambda;
9. executa novo apply do banco para liberar acesso da Lambda;
10. publica o codigo da Lambda;
11. integra `POST /auth/cpf` no API Gateway;
12. publica `OFICINA_PUBLIC_BASE_URL` no environment do repo da API com o endpoint do API Gateway;
13. publica a aplicacao no EKS;
14. captura o LoadBalancer da aplicacao;
15. integra `ANY /{proxy+}` no API Gateway;
16. valida outputs finais;
17. executa smoke tests quando solicitado.

### Destruir Ambiente Homolog

Workflow:

```text
.github/workflows/destroy-homolog.yml
```

Execucao:

```text
Actions -> Destruir Ambiente Homolog -> Run workflow
confirm=DESTRUIR
```

O workflow remove:

1. workloads da aplicacao no EKS;
2. Service `LoadBalancer`;
3. Load Balancers da AWS;
4. integracoes dependentes do API Gateway;
5. Lambda Auth CPF + senha;
6. RDS PostgreSQL;
7. node group;
8. EKS;
9. API Gateway;
10. ECR;
11. security groups;
12. route tables;
13. internet gateway;
14. subnets;
15. VPC.

Ao final, a esteira valida EKS, API Gateway, ECR, VPC, RDS, Lambda, ENIs e snapshots residuais do projeto.

### Provisionar Ambiente Prod

Workflow:

```text
.github/workflows/provision-prod.yml
```

Execucao:

```text
Actions -> Provisionar Ambiente Prod -> Run workflow
confirm=PROVISIONAR_PROD
run_smoke_tests=false ou true
```

O workflow executa a mesma orquestracao de homolog usando o GitHub Environment `prod`, state remoto de producao e aprovacao manual configurada no environment.

### Destruir Ambiente Prod

Workflow:

```text
.github/workflows/destroy-prod.yml
```

Execucao:

```text
Actions -> Destruir Ambiente Prod -> Run workflow
confirm=DESTRUIR_PROD
```

O workflow executa a mesma ordem segura de teardown de homolog usando o GitHub Environment `prod`. O banco de producao preserva o comportamento do repo `oficina-dgcar-infra-db`: deletion protection no apply e snapshot final no destroy.

## Preflight

Os scripts ficam em:

```text
scripts/preflight/
```

Eles validam:

- identidade AWS;
- regiao AWS;
- bucket e key do state;
- ausencia de `.tflock`;
- secrets e variables obrigatorios;
- environments do GitHub;
- VPC residual com CIDR do ambiente (`10.40.0.0/16` em `homolog`, `10.50.0.0/16` em `prod`);
- subnets residuais com CIDRs do ambiente;
- dependencias de VPC durante destroy.

Quando existe recurso residual conflitante, o provisionamento para antes do `apply`.

O ECR tambem e separado por ambiente quando ambos coexistem na mesma conta AWS: `homolog` mantem `oficina-dgcar/oficina-api` e `prod` usa `oficina-dgcar/prod-oficina-api`.

## Secrets E Variables

Secrets esperados no environment `homolog` deste repositorio:

- `AWS_ACCESS_KEY_ID`;
- `AWS_SECRET_ACCESS_KEY`;
- `GH_AUTOMATION_TOKEN`;
- `TF_STATE_BUCKET`;
- `TF_STATE_KEY`;
- `GH_ACTIONS_IAM_USER_ARN`;
- `GH_ACTIONS_IAM_USER_NAME`.
- `NEW_RELIC_LICENSE_KEY`.

Variables esperadas:

- `AWS_REGION`.

Smoke tests usam:

- `CLIENT_TEST_CPF`;
- `CLIENT_TEST_PASSWORD`;
- `CLIENT_TEST_OS_NUMBER`;
- `CLIENT_OTHER_OS_NUMBER`.

Os repositorios dependentes continuam com seus proprios secrets de banco, JWT, Mailtrap, deploy e runtime.

## Observabilidade Kubernetes

O Terraform instala o chart oficial `nri-bundle` da New Relic no namespace `newrelic`.

A integracao cobre:

- CPU e memoria de nodes, pods e containers;
- pods, status e restarts;
- eventos Kubernetes;
- estado de workloads e HPA via kube-state-metrics;
- health operacional por readiness/liveness e disponibilidade dos pods.

Logs de containers ficam desabilitados nesta fase para controlar ingestao. A API ja envia telemetria APM pelo Java Agent no repositorio `oficina-dgcar-api`.

Secret obrigatorio no environment do `oficina-dgcar-infra-k8s`:

```text
NEW_RELIC_LICENSE_KEY
```

Depois do provisionamento, a validacao visual ocorre em:

```text
New Relic -> Kubernetes
New Relic -> All Entities -> oficina-dgcar-homolog-eks ou oficina-dgcar-prod-eks
```

## Outputs Publicados

Este repositorio publica:

- `VPC_ID`;
- `PRIVATE_SUBNET_IDS`;
- `ALLOWED_DB_SECURITY_GROUP_IDS`;
- `ECR_REPOSITORY`;
- `EKS_CLUSTER_NAME`.
- `new_relic_kubernetes_enabled`;
- `new_relic_kubernetes_namespace`;
- `new_relic_kubernetes_release`.

Os demais repositorios publicam seus proprios outputs durante os workflows chamados pela esteira.

## Terraform State

Backend remoto:

```hcl
terraform {
  backend "s3" {}
}
```

Inicializacao remota:

```bash
terraform init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=$TF_STATE_KEY" \
  -backend-config="region=$AWS_REGION" \
  -backend-config="use_lockfile=true"
```

O backend usa `use_lockfile=true`.

`dynamodb_table` nao e usado.

## Validacao Local

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

Validacao dos manifests:

```bash
kubectl kustomize k8s > rendered-k8s.yaml
test -s rendered-k8s.yaml
```

## Tratamento De Falhas

Lock Terraform ativo bloqueia o workflow antes do `apply` ou `destroy`.

VPC ou subnet residual fora do state bloqueia o provisionamento.

EKS parcial fora do state bloqueia continuidade ate o state ser saneado ou o ambiente ser removido.

ENIs presas sao listadas com description, subnet, security group e attachment.

RDS em `homolog` usa destroy sem snapshot final fixo.

Erro 404 ao limpar secret ou variable significa recurso ja ausente.

## Origem Historica

O commit de origem e a rastreabilidade da extracao estao registrados em [`ORIGEM_HISTORICA.md`](./ORIGEM_HISTORICA.md).
