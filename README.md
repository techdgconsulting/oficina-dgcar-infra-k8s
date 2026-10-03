# oficina-dgcar-infra-k8s

Repositório da infraestrutura Kubernetes e borda de entrada da Oficina Mecânica DGCar no Tech Challenge 3.

## Propósito

- Provisionar EKS.
- Provisionar ECR.
- Provisionar API Gateway.
- Integrar API Gateway com a aplicação no EKS.
- Integrar API Gateway com a Lambda Auth CPF.
- Manter manifests Kubernetes, Kustomize/Helm, HPA, namespace, service e deployment base.

## Tecnologia Alvo

- Terraform
- AWS EKS
- AWS ECR
- AWS API Gateway
- Kubernetes
- Kustomize ou Helm
- GitHub Actions

## Branches E Ambientes

- `main`: produção, protegida e sem commits diretos.
- `homolog`: homologação, com deploy automático quando configurado.
- GitHub Environments esperados: `homolog` e `prod`.

## Secrets Esperados

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `TF_STATE_BUCKET`
- `TF_STATE_KEY`
- `TF_LOCK_TABLE`, se aplicável
- `NEW_RELIC_LICENSE_KEY`, se a integração Kubernetes for aplicada por este repositório

## Relação Com Os Demais Repositórios

- Consome outputs de banco do `oficina-dgcar-infra-db`.
- Consome imagem publicada pelo `oficina-dgcar-api`.
- Integra a Lambda do `oficina-dgcar-auth-lambda` ao API Gateway.

## Status

Extração inicial realizada a partir do repositório histórico.

Artefatos extraídos:

- `k8s/**`
- Terraform inicial de VPC, EKS, ECR e IAM em `terraform/**`
- Workflow Terraform em `.github/workflows/terraform.yml`

O commit de origem está registrado em [`ORIGEM_HISTORICA.md`](./ORIGEM_HISTORICA.md).

## Outputs Para Outros Repositórios

Este repositório deve publicar outputs consumidos por outros repositórios:

- `vpc_id`
- `private_subnet_ids`
- `eks_cluster_security_group_id`
- `ecr_repository_url`
- `eks_cluster_name`

`oficina-dgcar-infra-db` depende desses outputs para criar o RDS PostgreSQL com conectividade controlada.
