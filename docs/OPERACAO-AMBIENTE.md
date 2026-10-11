# Operacao Do Ambiente AWS

Este documento concentra a operacao do ambiente AWS da Oficina DGCar Tech Challenge 3.

O provisionamento e o teardown sao centralizados no repositorio `oficina-dgcar-infra-k8s`. Este repositorio executa a esteira principal e aciona os repositorios dependentes na ordem operacional correta.

## Workflows Operacionais

| Operacao | Repositorio | Workflow | Ambiente | Confirmacao |
|---|---|---|---|---|
| Provisionamento completo | `oficina-dgcar-infra-k8s` | `Provisionar Ambiente Homolog` / `Provisionar Ambiente Prod` | `homolog` / `prod` | `PROVISIONAR` |
| Teardown completo | `oficina-dgcar-infra-k8s` | `Destruir Ambiente Homolog` / `Destruir Ambiente Prod` | `homolog` / `prod` | `DESTROY` |

## Secrets Da Esteira Central

Configurar os secrets abaixo no GitHub Environment correspondente (`homolog` ou `prod`) do repositorio `oficina-dgcar-infra-k8s`.

| Secret | Uso |
|---|---|
| `AWS_ACCESS_KEY_ID` | Autenticacao AWS usada pelo Terraform da infraestrutura Kubernetes |
| `AWS_SECRET_ACCESS_KEY` | Autenticacao AWS usada pelo Terraform da infraestrutura Kubernetes |
| `AWS_REGION` | Regiao AWS da execucao, com `us-east-1` como valor operacional |
| `GH_AUTOMATION_TOKEN` | Aciona os repositorios dependentes e acompanha as execucoes |
| `TF_STATE_BUCKET` | Bucket S3 do state remoto da infraestrutura Kubernetes |
| `TF_STATE_KEY` | Chave do state remoto da infraestrutura Kubernetes |
| `GH_ACTIONS_IAM_USER_ARN` | Usuario IAM usado pela esteira para operar ECR e EKS |
| `GH_ACTIONS_IAM_USER_NAME` | Nome do usuario IAM usado pela esteira |

O token `GH_AUTOMATION_TOKEN` precisa de permissao para disparar workflows, consultar execucoes e gravar secrets de environment quando outputs tecnicos precisam ser compartilhados entre repositorios.

As credenciais AWS continuam configuradas nos environments dos repositorios que executam recursos proprios. A esteira central aciona essas execucoes e acompanha a conclusao.

## Secrets Da Validacao Funcional

Os secrets abaixo sao usados somente quando o input `run_smoke_tests=true` e existe massa de dados no banco.

| Secret | Uso |
|---|---|
| `CLIENT_TEST_CPF` | CPF de cliente existente no banco |
| `CLIENT_TEST_PASSWORD` | Senha desse cliente |
| `CLIENT_TEST_OS_NUMBER` | Numero de OS pertencente ao CPF autenticado |
| `CLIENT_OTHER_OS_NUMBER` | Numero de OS de outro cliente para validar bloqueio |

O provisionamento de infraestrutura nao depende desses valores.

## Provisionamento Completo

Execucao:

```text
Repositorio: oficina-dgcar-infra-k8s
Actions -> Provisionar Ambiente Homolog ou Provisionar Ambiente Prod
environment=homolog ou prod
confirm=PROVISIONAR
run_smoke_tests=false
```

Fluxo executado:

1. Valida secrets obrigatorios, identidade AWS e lock ativo do Terraform.
2. Inicializa o Terraform com backend S3 e `use_lockfile=true`.
3. Valida recursos residuais conflitantes antes de criar a infraestrutura.
4. Remove node group anterior preso em `CREATE_FAILED`, quando existir.
5. Provisiona VPC, subnets, EKS, ECR e API Gateway base.
6. Publica outputs de rede, EKS e ECR nos repositorios dependentes.
7. Aciona o provisionamento do PostgreSQL gerenciado.
8. Aciona o provisionamento da Lambda Auth CPF + Senha.
9. Atualiza o acesso do PostgreSQL ao security group real da Lambda.
10. Publica o pacote da Lambda.
11. Atualiza o API Gateway com a rota `POST /auth/cpf`.
12. Publica a aplicacao Spring Boot no EKS.
13. Resolve o endpoint HTTP da aplicacao e atualiza o API Gateway com a rota proxy `ANY /{proxy+}`.
14. Resolve os outputs finais do ambiente.
15. Executa smoke tests quando `run_smoke_tests=true`.

## Validacao Funcional

Depois do provisionamento, a validacao demonstravel usa:

1. health da aplicacao no EKS;
2. `POST /auth/cpf` com CPF e senha validos;
3. JWT `CLIENTE` retornado pela Lambda;
4. consulta protegida da OS por numero usando `Authorization: Bearer <accessToken>`;
5. chamadas negativas sem token, com token invalido e com OS de outro cliente.

## Teardown Completo

Execucao:

```text
Repositorio: oficina-dgcar-infra-k8s
Actions -> Destruir Ambiente Homolog ou Destruir Ambiente Prod
environment=homolog ou prod
confirm=DESTROY
```

Fluxo executado:

1. Valida secrets obrigatorios, identidade AWS e lock ativo do Terraform.
2. Remove workloads Kubernetes e Services `LoadBalancer` publicados pela aplicacao.
3. Aciona o destroy do PostgreSQL gerenciado com configuracao do ambiente selecionado.
4. Aciona o destroy da Lambda Auth CPF + Senha.
5. Aguarda liberacao de ENIs gerenciadas pela AWS.
6. Remove dependencias residuais seguras da VPC alvo.
7. Executa o destroy final da infraestrutura Kubernetes, API Gateway, ECR, EKS e rede.
8. Executa diagnostico adicional e nova tentativa quando a VPC ainda possui dependencias removiveis.
9. Valida que os recursos principais nao permanecem na AWS.

## Falhas Tratadas Pela Automacao

| Falha historica | Tratamento implementado |
|---|---|
| API Gateway com URI invalida | Rotas dependentes sao aplicadas depois dos outputs reais da Lambda e da API |
| RDS bloqueado por Free Tier | `homolog` usa parametros compativeis com ambiente academico |
| RDS com snapshot final duplicado | `homolog` usa `skip_final_snapshot=true` |
| RDS com deletion protection | `homolog` persiste `deletion_protection=false` antes do destroy |
| Lambda destroy sem pacote ZIP | Workflow da Lambda empacota antes do destroy |
| Secret `AUTH_LAMBDA_*` ausente | Limpeza idempotente registra ausencia e continua |
| Backend S3 com parametro depreciado | Workflows usam `use_lockfile=true` |
| AWS region ausente | Jobs usam `AWS_REGION` com fallback operacional `us-east-1` |
| Kubectl sem credenciais | Workflows atualizam kubeconfig antes de operar o cluster |
| VPC com SG residual de EKS | Scripts removem SGs residuais sem ENI antes do destroy final |
| EKS node group preso em `CREATE_FAILED` | Esteira remove o node group falho antes de novo provisionamento |
