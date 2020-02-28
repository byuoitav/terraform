module "acs" {
  source            = "github.com/byuoitav/terraform//modules/acs-info"
  env               = "prd"
  department_name   = "av"
  vpc_vpn_to_campus = true
}

data "aws_ssm_parameter" "acm_cert_arn" {
  name = "/acm/av-cert-arn"
}

data "aws_ssm_parameter" "r53_zone_id" {
  name = "/route53/zone/av-id"
}

data "aws_ssm_parameter" "eks_lb_name" {
  name = "/eks/lb-name"
}

data "aws_ssm_parameter" "eks_cluster_name" {
  name = "/eks/av-cluster-name"
}

data "aws_ssm_parameter" "role_boundary" {
  name = "/acs/iam/iamRolePermissionBoundary"
}

data "aws_lb" "eks_lb" {
  name = data.aws_ssm_parameter.eks_lb_name.value
}

data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "selected" {
  name = data.aws_ssm_parameter.eks_cluster_name
}

data "aws_iam_policy_document" "eks_oidc_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.selected.identity.0.oidc.0.issuer, "https://", "")}:sub"
      values = [
        "system:serviceaccount:default:${var.name}",
      ]
    }

    principals {
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.selected.identity.0.oidc.0.issuer, "https://", "")}"
      ]
      type = "Federated"
    }
  }
}

resource "aws_iam_role" "this" {
  count = var.iam_policy_doc == "" ? 0 : 1
  name  = "eks-${data.aws_ssm_parameter.eks_av_cluster_name}-${var.name}"

  assume_role_policy  = data.aws_iam_policy_document.eks_oidc_assume_role.json
  permission_boundary = data.aws_ssm_parameter.role_boundary

  tags = {
    env  = "prd"
    repo = var.repo_url
  }

}

resource "aws_iam_policy" "this" {
  count = var.iam_policy_doc == "" ? 0 : 1

  name   = "eks-${data.aws_ssm_parameter.eks_av_cluster_name}-${var.name}"
  policy = var.iam_policy_doc
}

resource "aws_iam_policy_attachment" "this" {
  count = var.iam_policy_doc == "" ? 0 : 1

  policy_arn = aws_iam_policy.this.arn
  role       = aws_iam_role.this.name
}

resource "kubernetes_service_account" "this" {
  count = var.iam_policy_doc == "" ? 0 : 1

  metadata {
    name = var.name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.this.arn
    }

    labels = {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_deployment" "this" {
  metadata {
    name = var.name

    labels = {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/version"    = var.image_version
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = var.name
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"    = var.name
          "app.kubernetes.io/version" = var.image_version
        }
      }

      spec {
        image_pull_secrets {
          name = length(var.image_pull_secret) > 0 ? var.image_pull_secret : null
        }

        container {
          name              = "server"
          image             = "${var.image}:${var.image_version}"
          image_pull_policy = "Always"

          args = var.container_args

          port {
            container_port = var.container_port
          }

          // environment vars
          dynamic "env" {
            for_each = var.container_env

            content {
              name  = env.key
              value = env.value
            }
          }

          // Volume mounts
          dynamic "volume_mount" {

            for_each = var.iam_policy_doc == "" ? [] : [kubernetes_service_account.this.default_secret_name]

            content {
              mount_path = "/var/run/secrets/kubernetes.io/serviceaccount"
              name       = volume_mount
              read_only  = true
            }

          }

          // container is killed it if fails this check
          liveness_probe {
            http_get {
              port = var.container_port
              path = "/healthz"
            }

            initial_delay_seconds = 60
            period_seconds        = 60
            timeout_seconds       = 3
          }

          // container is isolated from new traffic if fails this check
          readiness_probe {
            http_get {
              port = var.container_port
              path = "/healthz"
            }

            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 3
          }
        }
      }
    }
  }

  timeouts {
    create = "5m"
    update = "5m"
    delete = "10m"
  }
}

// let everyone get to this service at one IP
resource "kubernetes_service" "this" {
  metadata {
    name = var.name

    labels = {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    type = "ClusterIP"
    port {
      port        = 80
      target_port = var.container_port
    }

    selector = {
      "app.kubernetes.io/name" = var.name
    }
  }
}

// create the route53 entry
resource "aws_route53_record" "this" {
  count = length(var.public_urls)

  zone_id = data.aws_ssm_parameter.r53_zone_id.value
  name    = var.public_urls[count.index]
  type    = "A"

  alias {
    name                   = data.aws_lb.eks_lb.dns_name
    zone_id                = data.aws_lb.eks_lb.zone_id
    evaluate_target_health = false
  }
}

resource "kubernetes_ingress" "this" {
  // only create the ingress if there is at least one public url
  count = length(var.public_urls) > 0 ? 1 : 0

  metadata {
    name = var.name

    labels = {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/managed-by" = "terraform"
    }

    annotations = merge(var.ingress_annotations, {
      "kubernetes.io/ingress.class"                    = "nginx"
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "true"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
    })
  }

  spec {
    tls {
      secret_name = "star-av-byu-edu"
      hosts       = var.public_urls
    }

    dynamic "rule" {
      for_each = var.public_urls

      content {
        host = rule.value

        http {
          path {
            backend {
              service_name = kubernetes_service.this.metadata.0.name
              service_port = 80
            }
          }
        }
      }
    }
  }
}
