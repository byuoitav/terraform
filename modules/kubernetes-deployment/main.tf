module "acs" {
  source            = "github.com/byuoitav/terraform//modules/acs-info"
  env               = "prd"
  department_name   = "av"
  vpc_vpn_to_campus = true
}

data "aws_ssm_parameter" "acm_cert_arn" {
  name = "/acm/av-cert-arn"
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

          readiness_probe {
            http_get {
              port = var.container_port
              path = "/status"
            }

            initial_delay_seconds = 30
            period_seconds        = 60
            timeout_seconds       = 3
          }

          liveness_probe {
            http_get {
              port = var.container_port
              path = "/status"
            }

            initial_delay_seconds = 60
            period_seconds        = 30
            timeout_seconds       = 3
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

resource "kubernetes_ingress" "this" {
  // only create the ingress if the public url is set
  count = length(var.public_url) > 0 ? 1 : 0

  metadata {
    name = var.name

    labels = {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/managed-by" = "terraform"
    }

    annotations = {
      "kubernetes.io/ingress.class"               = "alb"
      "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"     = "ip"
      "alb.ingress.kubernetes.io/subnets"         = join(",", module.acs.public_subnet_ids)
      "alb.ingress.kubernetes.io/certificate-arn" = data.aws_ssm_parameter.acm_cert_arn.value
      "alb.ingress.kubernetes.io/listen-ports" = jsonencode([
        { HTTP = 80 },
        { HTTPS = 443 }
      ])

      "alb.ingress.kubernetes.io/actions.ssl-redirect" = jsonencode({
        Type = "redirect"
        RedirectConfig = {
          Protocol   = "HTTPS"
          Port       = "443"
          StatusCode = "HTTP_301"
        }
      })

      "alb.ingress.kubernetes.io/tags" = "env=prd,data-sensitivity=internal,repo=${var.repo_url}"
    }
  }

  spec {
    rule {
      host = var.public_url

      http {
        // redirect to https
        path {
          backend {
            service_name = "ssl-redirect"
            service_port = "use-annotation"
          }
        }

        // forward to nodeport
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
