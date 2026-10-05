# oficina-dgcar-infra-k8s

Infraestrutura Terraform de Kubernetes, registry e borda de entrada da Oficina Mecanica DGCar.

## Proposito

Este repositorio provisiona e documenta a infraestrutura de execucao da aplicacao:

- VPC, subnets e rotas base;
- Amazon EKS;
- Amazon ECR;
- API Gateway HTTP;
- integracao API Gateway para a API em Kubernetes;
- integracao API Gateway para a Lambda de autenticacao por CPF;
- manifests Kubernetes da aplicacao principal;
- HPA, namespace, service, deployment, configmap e secret example.

## Tecnologias

- Terraform;
- AWS EKS;
- AWS ECR;
- AWS API Gateway;
- Kubernetes;
- Kustomize;
- GitHub Actions.

## Separacao De Responsabilidades

Este repositorio nao provisiona o RDS PostgreSQL e nao contem codigo da aplicacao Java ou da Lambda.

Outputs publicados para outros repositorios:

- `vpc_id`;
- `public_subnet_ids`;
- `private_subnet_ids`;
- `eks_cluster_security_group_id`;
- `ecr_repository_url`;
- `eks_cluster_name`;
- `eks_cluster_endpoint`;
- `api_gateway_id`;
- `api_gateway_endpoint`;
- `api_gateway_execution_arn`.

Entradas esperadas de outros repositorios:

- `auth_lambda_invoke_arn`, produzido por `oficina-dgcar-auth-lambda`;
- `auth_lambda_function_name`, produzido por `oficina-dgcar-auth-lambda`;
- `api_backend_url`, endpoint HTTP da aplicacao exposta no Kubernetes;
- dados de conexao do banco, produzidos por `oficina-dgcar-infra-db`, aplicados via Secret/ConfigMap.

## API Gateway

O API Gateway HTTP e criado como entrada oficial da solucao.

Integracoes configuradas:

- rota `POST /auth/cpf`, integrada a Lambda de autenticacao por CPF quando `AUTH_LAMBDA_INVOKE_ARN` e `AUTH_LAMBDA_FUNCTION_NAME` existem;
- rota `ANY /{proxy+}`, integrada ao backend da aplicacao quando `API_BACKEND_URL` existe.

`API_BACKEND_URL` foi tratado como entrada opcional. Quando o valor esta ausente ou vazio, a integracao HTTP da aplicacao nao e criada. Esse comportamento permite provisionar primeiro a infraestrutura base de VPC, EKS, ECR e API Gateway, antes da aplicacao principal estar exposta em Kubernetes.

Fluxo aplicado:

1. Primeiro `apply`: cria rede, EKS, ECR e API Gateway sem rota proxy da aplicacao quando `API_BACKEND_URL` esta vazio.
2. Deploy da aplicacao: publica o backend HTTP da API em Kubernetes.
3. Novo `apply`: cria ou atualiza a rota `ANY /{proxy+}` apontando para `API_BACKEND_URL`.

Da mesma forma, a rota `POST /auth/cpf` so e integrada quando os outputs da Lambda ja foram publicados pelo repositorio `oficina-dgcar-auth-lambda`.

Permissao de invocacao da Lambda:

- a rota `POST /auth/cpf` usa integracao `AWS_PROXY` com a Lambda Auth CPF;
- a permissao `lambda:InvokeFunction` foi criada com `SourceArn` explicito no formato `arn:aws:execute-api:<regiao>:<account-id>:<api-id>/*/*`;
- esse formato garante que o API Gateway consiga invocar a Lambda no mesmo account AWS;
- quando o `SourceArn` fica sem `account-id`, a chamada pode retornar `500 Internal Server Error` no API Gateway sem gerar logs de execucao na Lambda;
- apos alteracao dessa permissao, o `apply` do Terraform em `homolog` atualiza a policy da Lambda e a rota `POST /auth/cpf` passa a encaminhar chamadas para a funcao.

Endpoint homolog atual:

```text
POST https://vqgo7dwgqj.execute-api.us-east-1.amazonaws.com/auth/cpf
```

## State Terraform

O backend remoto usa S3 com lockfile nativo:

```text
use_lockfile=true
```

Secrets esperados:

- `AWS_ACCESS_KEY_ID`;
- `AWS_SECRET_ACCESS_KEY`;
- `AWS_REGION`;
- `TF_STATE_BUCKET`;
- `TF_STATE_KEY`;
- `GH_AUTOMATION_TOKEN`;
- `GH_ACTIONS_IAM_USER_ARN`;
- `API_BACKEND_URL`;
- `AUTH_LAMBDA_INVOKE_ARN`;
- `AUTH_LAMBDA_FUNCTION_NAME`;
- `NEW_RELIC_LICENSE_KEY`, quando a integracao Kubernetes for habilitada.

Chaves de state definidas:

- homologacao: `homolog/infra-k8s/terraform.tfstate`;
- producao: `prod/infra-k8s/terraform.tfstate`.

## Pipeline

Pull Requests executam:

- `terraform fmt -check -recursive`;
- `terraform init`;
- `terraform validate`;
- `terraform plan`;
- renderizacao dos manifests com `kubectl kustomize`;
- verificacao do manifesto renderizado sem depender de cluster ativo.

Push em `homolog` ou `main` executa validacao e plan offline.

Apply real e disparado manualmente por `workflow_dispatch`, usando `action=apply` e o environment desejado. O environment `prod` esta sujeito a aprovacao no GitHub.

Depois do `terraform apply`, o workflow publica automaticamente os outputs de rede nos repos dependentes.

## Acesso Do GitHub Actions Ao EKS

O EKS usa access entries para autorizar o principal IAM que executa `kubectl` nos workflows.

Foi configurado no environment `homolog` o secret:

```text
GH_ACTIONS_IAM_USER_ARN=arn:aws:iam::857145323352:user/16soat-tf
```

Esse ARN e passado para o Terraform como `TF_VAR_github_actions_iam_user_arn` durante `plan` e `apply`.

Recursos Terraform responsaveis:

- `aws_eks_access_entry.github_actions`;
- `aws_eks_access_policy_association.github_actions_cluster_admin`.

Permissao aplicada:

```text
arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
```

Evidencia operacional em `homolog`:

```bash
aws eks list-access-entries \
  --region us-east-1 \
  --cluster-name oficina-dgcar-homolog-eks

aws eks list-associated-access-policies \
  --region us-east-1 \
  --cluster-name oficina-dgcar-homolog-eks \
  --principal-arn arn:aws:iam::857145323352:user/16soat-tf
```

O erro abaixo indica ausencia desse access entry ou da policy associada:

```text
failed to download openapi: the server has asked for the client to provide credentials
```

Correcao aplicada em `homolog`:

- access entry criado para `arn:aws:iam::857145323352:user/16soat-tf`;
- policy `AmazonEKSClusterAdminPolicy` associada em escopo `cluster`;
- `kubectl get namespace` validado com sucesso apos a associacao.

Secrets gravados em `oficina-dgcar-auth-lambda`:

- `VPC_ID`;
- `PRIVATE_SUBNET_IDS`.

Secrets gravados em `oficina-dgcar-infra-db`:

- `VPC_ID`;
- `PRIVATE_SUBNET_IDS`;
- `ALLOWED_DB_SECURITY_GROUP_IDS`.

## Automacao Entre Repositorios

O workflow usa `GH_AUTOMATION_TOKEN` para gravar secrets nos repos dependentes via GitHub CLI. Esse token fica configurado nos environments `homolog` e `prod`.

Fluxo automatizado:

1. `oficina-dgcar-infra-k8s` executa `apply`.
2. Terraform publica `vpc_id`, `private_subnet_ids` e `eks_cluster_security_group_id`.
3. O workflow grava `VPC_ID` e `PRIVATE_SUBNET_IDS` no repo `oficina-dgcar-auth-lambda`.
4. O workflow grava `VPC_ID`, `PRIVATE_SUBNET_IDS` e `ALLOWED_DB_SECURITY_GROUP_IDS` no repo `oficina-dgcar-infra-db`.

## Execucao Local

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init -backend=false -reconfigure
terraform fmt -recursive
terraform validate
terraform plan
```

Para executar `terraform plan` sem acesso ao backend remoto, renomeie temporariamente `backend.tf` antes do `terraform init`.

Para validar manifests:

```bash
kubectl kustomize k8s
kubectl kustomize k8s > rendered-k8s.yaml
test -s rendered-k8s.yaml
```

## Origem Historica

O commit de origem e a rastreabilidade da extracao estao registrados em [`ORIGEM_HISTORICA.md`](./ORIGEM_HISTORICA.md).
