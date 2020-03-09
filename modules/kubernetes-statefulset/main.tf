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

data "aws_lb" "eks_lb" {
  name = data.aws_ssm_parameter.eks_lb_name.value
}

resource "kubernetes_storage_class" "this" {
  metadata {
    name = var.name

    labels = {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  storage_provisioner    = "kubernetes.io/aws-ebs"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true

  parameters = {
    type      = "gp2"
    fsType    = "ext4"
    encrypted = "true"
  }
}

resource "kubernetes_stateful_set" "this" {
  metadata {
    name = var.name

    labels = {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/version"    = var.image_version
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    service_name = var.name
    replicas     = 1

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
        dynamic "image_pull_secrets" {
          for_each = length(var.image_pull_secret) > 0 ? [var.image_pull_secret] : []

          content {
            name = image_pull_secrets.value
          }
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

          // TODO figure out how to do this for grpc
          //// container is killed it if fails this check
          //liveness_probe {
          //  http_get {
          //    port = var.container_port
          //    path = "/healthz"
          //  }

          //  initial_delay_seconds = 60
          //  period_seconds        = 60
          //  timeout_seconds       = 3
          //}

          //// container is isolated from new traffic if fails this check
          //readiness_probe {
          //  http_get {
          //    port = var.container_port
          //    path = "/healthz"
          //  }

          //  initial_delay_seconds = 30
          //  period_seconds        = 30
          //  timeout_seconds       = 3
          //}

          volume_mount {
            name       = "${var.name}-storage"
            mount_path = var.storage_mount_path
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "${var.name}-storage"

        labels = {
          "app.kubernetes.io/name"       = "${var.name}-storage"
          "app.kubernetes.io/managed-by" = "terraform"
        }
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = kubernetes_storage_class.this.metadata.0.name

        resources {
          requests = {
            storage = var.storage_request_size
          }
        }
      }
    }
  }
}

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
