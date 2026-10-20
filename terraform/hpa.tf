resource "kubernetes_env" "vpc_cni_prefix" {
  api_version   = "apps/v1"
  kind          = "DaemonSet"
  container     = "aws-node"
  field_manager = "oficina-hpa"
  force         = true
  metadata {
    name      = "aws-node"
    namespace = "kube-system"
  }
  env {
    name  = "ENABLE_PREFIX_DELEGATION"
    value = "true"
  }
  env {
    name  = "WARM_PREFIX_TARGET"
    value = "1"
  }
  env {
    name  = "WARM_IP_TARGET"
    value = "2"
  }
  depends_on = [aws_eks_node_group.main]
}

resource "kubernetes_config_map_v1" "node_pod_capacity" {
  metadata {
    name      = "oficina-node-pod-capacity"
    namespace = "kube-system"
  }
  data = {
    "configure.py" = file("${path.module}/node-pod-capacity.py")
  }
  depends_on = [aws_eks_node_group.main]
}

# One-shot configuration of the existing AL2023 node, not an extra worker node.
# A kubelet drop-in persists across reboots without changing EC2 type/count.
resource "kubernetes_job_v1" "node_pod_capacity" {
  metadata {
    name      = "oficina-node-pod-capacity-${substr(filesha256("${path.module}/node-pod-capacity.py"), 0, 8)}"
    namespace = "kube-system"
  }
  spec {
    backoff_limit           = 0
    active_deadline_seconds = 240
    template {
      metadata {
        labels = { "app.kubernetes.io/name" = "oficina-node-pod-capacity" }
      }
      spec {
        restart_policy                  = "Never"
        host_network                    = true
        host_pid                        = true
        dns_policy                      = "ClusterFirstWithHostNet"
        automount_service_account_token = false
        node_selector = {
          "eks.amazonaws.com/nodegroup" = aws_eks_node_group.main.node_group_name
        }
        container {
          name    = "configure"
          image   = "python:3.13-alpine"
          command = ["python", "-B", "/scripts/configure.py"]
          security_context {
            run_as_user               = 0
            privileged                = true
            read_only_root_filesystem = true
          }
          resources {
            requests = { cpu = "10m", memory = "16Mi" }
            limits   = { cpu = "100m", memory = "64Mi" }
          }
          volume_mount {
            name       = "host"
            mount_path = "/host"
          }
          volume_mount {
            name       = "script"
            mount_path = "/scripts"
            read_only  = true
          }
        }
        volume {
          name = "host"
          host_path {
            path = "/"
            type = "Directory"
          }
        }
        volume {
          name = "script"
          config_map {
            name = kubernetes_config_map_v1.node_pod_capacity.metadata[0].name
          }
        }
      }
    }
  }
  wait_for_completion = true
  timeouts {
    create = "5m"
    update = "5m"
  }
  depends_on = [kubernetes_env.vpc_cni_prefix]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.14.0"
  wait       = true
  timeout    = 300
  values = [yamlencode({
    replicas      = 1
    containerPort = 10251
    resources = {
      requests = { cpu = "25m", memory = "32Mi" }
      limits   = { cpu = "200m", memory = "128Mi" }
    }
    args = [
      "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
      "--kubelet-use-node-status-port",
      "--metric-resolution=15s"
    ]
  })]
  depends_on = [kubernetes_job_v1.node_pod_capacity, helm_release.new_relic_kubernetes]
}
