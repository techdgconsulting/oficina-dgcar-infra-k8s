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
5. publica outputs de rede para banco, Lambda e API;
6. executa o provisionamento do banco;
7. executa o provisionamento da Lambda;
8. executa novo apply do banco para liberar acesso da Lambda;
9. publica o codigo da Lambda;
10. integra `POST /auth/cpf` no API Gateway;
11. publica a aplicacao no EKS;
12. captura o LoadBalancer da aplicacao;
13. integra `ANY /{proxy+}` no API Gateway;
14. valida outputs finais;
15. executa smoke tests quando solicitado.

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
- VPC residual com CIDR `10.40.0.0/16`;
- subnets residuais com CIDRs `10.40.1.0/24`, `10.40.2.0/24`, `10.40.11.0/24` e `10.40.12.0/24`;
- dependencias de VPC durante destroy.

Quando existe recurso residual conflitante, o provisionamento para antes do `apply`.

## Secrets E Variables

Secrets esperados no environment `homolog` deste repositorio:

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
- `CLIENT_TEST_OS_NUMBER`.
- `CLIENT_OTHER_OS_NUMBER`.

Os repositorios dependentes continuam com seus proprios secrets de banco, JWT, Mailtrap, deploy e runtime.

## Outputs Publicados

Este repositorio publica:

- `VPC_ID`;
- `PRIVATE_SUBNET_IDS`;
- `ALLOWED_DB_SECURITY_GROUP_IDS`;
- `ECR_REPOSITORY`;
- `EKS_CLUSTER_NAME`.

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
