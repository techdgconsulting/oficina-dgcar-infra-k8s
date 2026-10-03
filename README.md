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

## State Terraform

O backend remoto usa S3 com lock em DynamoDB.

Secrets esperados:

- `AWS_ACCESS_KEY_ID`;
- `AWS_SECRET_ACCESS_KEY`;
- `AWS_REGION`;
- `TF_STATE_BUCKET`;
- `TF_STATE_KEY`;
- `TF_LOCK_TABLE`;
- `API_BACKEND_URL`;
- `AUTH_LAMBDA_INVOKE_ARN`;
- `AUTH_LAMBDA_FUNCTION_NAME`;
- `NEW_RELIC_LICENSE_KEY`, quando a integracao Kubernetes for habilitada.

Recomendacao de chaves de state:

- homologacao: `oficina-dgcar/infra-k8s/homolog/terraform.tfstate`;
- producao: `oficina-dgcar/infra-k8s/prod/terraform.tfstate`.

## Pipeline

Pull Requests executam:

- `terraform fmt -check -recursive`;
- `terraform init`;
- `terraform validate`;
- `terraform plan`;
- renderizacao dos manifests com `kubectl kustomize`;
- verificacao do manifesto renderizado sem depender de cluster ativo.

Push em `homolog` aplica no environment `homolog`.

Push em `main` aplica no environment `prod`, sujeito a aprovacao do environment no GitHub.

## Execucao Local

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init -backend=false
terraform fmt -recursive
terraform validate
terraform plan
```

Para validar manifests:

```bash
kubectl kustomize k8s
kubectl kustomize k8s > rendered-k8s.yaml
test -s rendered-k8s.yaml
```

## Origem Historica

O commit de origem e a rastreabilidade da extracao estao registrados em [`ORIGEM_HISTORICA.md`](./ORIGEM_HISTORICA.md).
