//terraform {
//  backend "s3" {
//    bucket     = "terraform-state-storage-586877430255"
//    lock_table = "terraform-state-lock-586877430255"
//    key        = "${var.name}.tfstate"
//    region     = "us-west-2"
//  }
//}

//provider "aws" {
//  region = "us-west-2"
//}

//data "aws_ssm_parameter" "eks_cluster_endpoint" {
//  name = "/eks/av-cluster-endpoint"
//}

//provider "kubernetes" {
//  host = data.aws_ssm_parameter.eks_cluster_endpoint.value
//}

data "aws_ssm_parameter" "acm_cert_arn" {
  name = "/acm/av-cert-arn"
}

module "acs" {
  source            = "github.com/byuoitav/terraform//modules/acs-info"
  env               = "prd"
  department_name   = "av"
  vpc_vpn_to_campus = true
}

resource "kubernetes_deployment" "this" {
  metadata {
    name = var.name

    labels = {
      "app.kubernetes.io/name"       = var.name
      "app.kubernetes.io/version"    = var.version
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
          "app.kubernetes.io/version" = var.version
        }
      }

      spec {
        container {
          name              = "server"
          image             = "${var.image}:${var.version}"
          image_pull_policy = "Always"

          args = var.container_args

          port {
            name           = "this"
            container_port = var.container_port
          }

          readiness_probe {
            http_get {
              port = "this"
              path = "/status"
            }

            initial_delay_seconds = 30
            period_seconds        = 60
            timeout_seconds       = 3
          }

          liveness_probe {
            http_get {
              port = "this"
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
      port = var.container_port
    }

    selector = {
      "app.kubernetes.io/name" = var.name
    }
  }
}

resource "kubernetes_ingress" "this" {
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
            service_port = var.container_port
          }
        }
      }
    }
  }
}
