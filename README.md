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

## Documentacao Central

A documentacao arquitetural completa do Tech Challenge 3 esta centralizada em:

[oficina-dgcar-docs](https://github.com/techdgconsulting/oficina-dgcar-docs)

Este repositorio mantem apenas a documentacao especifica da infraestrutura Kubernetes, registry, API Gateway, manifests, pipeline e deploy de borda.

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
- parameter mapping `overwrite:path = "/$request.path.proxy"` na integracao HTTP proxy da aplicacao, garantindo que chamadas como `/api/ordens-servico/cliente/1` cheguem ao Spring Boot com o path original.

`API_BACKEND_URL` foi tratado como entrada opcional. Quando o valor esta ausente ou vazio, a integracao HTTP da aplicacao nao e criada. Esse comportamento permite provisionar primeiro a infraestrutura base de VPC, EKS, ECR e API Gateway, antes da aplicacao principal estar exposta em Kubernetes.

Fluxo aplicado:

1. Primeiro `apply`: cria rede, EKS, ECR e API Gateway sem rota proxy da aplicacao quando `API_BACKEND_URL` esta vazio.
2. Deploy da aplicacao: publica o backend HTTP da API em Kubernetes.
3. Novo `apply`: cria ou atualiza a rota `ANY /{proxy+}` apontando para `API_BACKEND_URL`.

Da mesma forma, a rota `POST /auth/cpf` e uma integracao progressiva. Ela passa a ser criada quando os outputs da Lambda sao publicados pelo repositorio `oficina-dgcar-auth-lambda`.

O workflow de `apply` trata `AUTH_LAMBDA_INVOKE_ARN` e `AUTH_LAMBDA_FUNCTION_NAME` como entradas opcionais durante o provisionamento base. Sem esses outputs confirmados, o Terraform cria a infraestrutura de rede, EKS, ECR e API Gateway sem a rota `POST /auth/cpf`. Depois que `oficina-dgcar-auth-lambda` executa `apply-infra` e publica os outputs, um novo `apply` deste repositorio cria a integracao do API Gateway com a Lambda.

Permissao de invocacao da Lambda:

- a rota `POST /auth/cpf` usa integracao `AWS_PROXY` com a Lambda Auth CPF;
- a permissao `lambda:InvokeFunction` usa `SourceArn` explicito no formato `arn:aws:execute-api:<regiao>:<account-id>:<api-id>/*/*`;
- esse formato vincula a permissao ao API Gateway da mesma conta AWS;
- o `apply` do Terraform atualiza a policy da Lambda quando os outputs da funcao estao disponiveis.

Endpoint homolog atual:

```text
POST https://vqgo7dwgqj.execute-api.us-east-1.amazonaws.com/auth/cpf
```

Endpoint base homolog:

```text
https://vqgo7dwgqj.execute-api.us-east-1.amazonaws.com
```

Backend HTTP da aplicacao em Kubernetes cadastrado no environment `homolog`:

```text
API_BACKEND_URL=http://a0340e77e14674adbb11ba17cf6384d8-1700619956.us-east-1.elb.amazonaws.com
```

Esse valor foi obtido do Service `oficina-api` no EKS:

```powershell
aws eks update-kubeconfig --region us-east-1 --name oficina-dgcar-homolog-eks
kubectl get svc oficina-api -n oficina -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

O secret foi gravado no GitHub Environment `homolog` com:

```powershell
gh secret set API_BACKEND_URL `
  --repo techdgconsulting/oficina-dgcar-infra-k8s `
  --env homolog `
  --body "http://a0340e77e14674adbb11ba17cf6384d8-1700619956.us-east-1.elb.amazonaws.com"
```

Depois desse cadastro, o workflow manual `Infra K8s` com `action=apply` cria a rota `ANY /{proxy+}` no API Gateway.

Validacao esperada apos o `apply`:

```text
POST /auth/cpf -> 200 com accessToken
GET /api/ordens-servico/cliente/{clienteId} com Bearer token -> 200
GET /api/ordens-servico/cliente/{clienteId} sem token -> 401
GET /api/ordens-servico/cliente/{outroClienteId} com Bearer token de outro cliente -> 403
```

Quando `/auth/cpf` funciona mas chamadas para `/api/...` retornam:

```json
{
  "message": "Not Found"
}
```

Enquanto `API_BACKEND_URL` nao esta configurado no environment, o API Gateway permanece sem a rota proxy da aplicacao. Depois que a API publica o LoadBalancer, um novo `apply` deste repositorio cria a integracao `ANY /{proxy+}`.

Quando a chamada direta ao LoadBalancer retorna `200`, mas a mesma rota via API Gateway retorna `404` da aplicacao, a causa esperada e ausencia do parameter mapping de path na integracao HTTP proxy. O Terraform aplica:

```hcl
request_parameters = {
  "overwrite:path" = "/$request.path.proxy"
}
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

## Destroy Manual Do Ambiente Academico

Foi criada a action `Destroy Infra K8s` para desligar a infraestrutura deste repositorio apos validacoes academicas e evitar custo recorrente na AWS.

Essa automacao e manual, usa os secrets do GitHub Environment selecionado e exige confirmacao textual antes de executar qualquer remocao.

Execucao no GitHub:

1. Acessar `Actions`.
2. Selecionar `Destroy Infra K8s`.
3. Acionar `Run workflow`.
4. Escolher `action=cleanup-workloads` para remover workloads Kubernetes e Load Balancers antes dos destroys da Lambda e do banco.
5. Escolher `action=destroy` para destruir EKS, API Gateway, ECR, VPC, subnets e rede no final do teardown.
6. Escolher o environment `homolog` ou `prod`.
7. Preencher `confirm_destroy` com o valor exato `DESTROY`.

Quando o environment selecionado possui required reviewers, o GitHub solicita aprovacao antes da execucao. No `homolog`, a execucao segue direto apos o `Run workflow` porque o environment nao possui aprovacao obrigatoria configurada.

Com `action=cleanup-workloads`, o workflow executa:

- leitura do state remoto Terraform em S3;
- obtencao dos outputs `vpc_id` e `eks_cluster_name`;
- remocao dos recursos Kubernetes da aplicacao no namespace `oficina`;
- remocao de Load Balancers Classic e ELBv2 criados pelo Kubernetes dentro da VPC;
- remocao de security groups orfaos criados por Services Kubernetes do tipo `LoadBalancer`.

Com `action=destroy`, o workflow executa os passos acima e tambem:

- execucao de `terraform destroy`;
- remocao de security groups orfaos criados por Services Kubernetes do tipo `LoadBalancer`;
- nova tentativa de `terraform destroy` para concluir a exclusao de subnets, internet gateway e VPC apos a limpeza de dependencias.

Esse fluxo cobre os recursos deste repositorio:

- EKS;
- node group;
- ECR;
- API Gateway;
- VPC, subnets, route tables, NAT/Internet Gateway e security groups gerenciados pelo Terraform;
- recursos auxiliares criados pelo Kubernetes que impedem a exclusao completa da VPC quando ficam orfaos.

A action nao e executada em push, Pull Request ou merge. O cleanup e o destroy real so ocorrem por `workflow_dispatch` com `confirm_destroy=DESTROY`.

O destroy deste repositorio nao remove recursos que pertencem a outros repositorios:

- RDS PostgreSQL fica sob responsabilidade de `oficina-dgcar-infra-db`;
- Lambda Auth CPF, IAM Role e Log Group da Lambda ficam sob responsabilidade de `oficina-dgcar-auth-lambda`;
- imagem e deploy da aplicacao ficam sob responsabilidade de `oficina-dgcar-api`.

Para teardown completo do ambiente academico, a ordem operacional aplicada e:

1. executar `Destroy Infra K8s` com `action=cleanup-workloads`, removendo workloads Kubernetes da aplicacao e Load Balancers publicados pelo Service `oficina-api`;
2. executar `destroy` no repo `oficina-dgcar-infra-db`, removendo RDS PostgreSQL, subnet group, security group do banco e a regra que referencia o security group da Lambda;
3. executar `destroy-infra` no repo `oficina-dgcar-auth-lambda`, removendo Function, Log Group, IAM e security group da Lambda;
4. aguardar alguns minutos para a AWS liberar as ENIs gerenciadas da Lambda e do RDS;
5. executar `Destroy Infra K8s` com `action=destroy`, finalizando EKS, API Gateway, ECR, VPC, subnets, rotas e recursos auxiliares criados pelo Kubernetes.

Essa ordem evita falhas por dependencia entre Load Balancers, security groups, subnets, Lambda, API Gateway e RDS. O banco sai antes da Lambda porque o security group do RDS referencia o security group da Lambda como origem autorizada para PostgreSQL. A rede fica por ultimo porque as subnets so podem ser removidas depois que as ENIs gerenciadas da Lambda e do RDS deixam de existir.

## Sequencia Completa De Provisionamento

A criacao completa do ambiente AWS em `homolog` segue esta ordem:

1. `oficina-dgcar-infra-k8s`: executar `Infra K8s` com `action=apply` para criar rede, EKS, ECR e API Gateway base, ainda sem rotas dependentes da Lambda ou da aplicacao.
2. `oficina-dgcar-infra-db`: executar `Infra DB` com `action=apply` para criar o RDS PostgreSQL na rede publicada pelo repo Kubernetes.
3. `oficina-dgcar-auth-lambda`: executar `Auth CPF Lambda` com `action=apply-infra` para criar a Lambda Auth CPF + Senha, IAM, Log Group e security group.
4. `oficina-dgcar-infra-db`: executar novo `apply` para liberar o PostgreSQL ao security group publicado pela Lambda.
5. `oficina-dgcar-auth-lambda`: executar `Auth CPF Lambda` com `action=deploy-code` para publicar o pacote da funcao.
6. `oficina-dgcar-infra-k8s`: executar novo `apply` para criar ou atualizar a integracao `POST /auth/cpf` do API Gateway com a Lambda.
7. `oficina-dgcar-api`: executar `App CI/CD - Build, Test and Deploy` para publicar a aplicacao no EKS e gravar automaticamente `API_BACKEND_URL` neste repositorio.
8. `oficina-dgcar-infra-k8s`: executar novo `apply` para criar a rota proxy `ANY /{proxy+}` apontando para o backend Kubernetes.

Essa sequencia foi definida porque os repositorios trocam outputs por GitHub Secrets/Variables. A Lambda depende dos outputs de rede e banco; o banco precisa conhecer o security group da Lambda para liberar a conexao PostgreSQL; o Gateway depende dos outputs da Lambda para `/auth/cpf`; e a rota proxy da API usa o endpoint HTTP publicado automaticamente depois do deploy da aplicacao.

## Acesso Do GitHub Actions Ao EKS

O EKS usa access entries para autorizar o principal IAM que executa `kubectl` nos workflows.

Foi configurado no environment `homolog` o secret:

```text
GH_ACTIONS_IAM_USER_ARN=arn:aws:iam::857145323352:user/16soat-tf
GH_ACTIONS_IAM_USER_NAME=16soat-tf
```

Esses valores sao passados para o Terraform durante `plan` e `apply`. Quando `GH_ACTIONS_IAM_USER_ARN` existe no environment, o workflow habilita a criacao do acesso Kubernetes para o principal IAM usado pelas esteiras.

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

O acesso do GitHub Actions ao Kubernetes depende de access entry e policy associada no EKS. Configuracao aplicada em `homolog`:

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
