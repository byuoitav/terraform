variable "name" {
  description = "The name of the service. Must be unique across the cluster."
  type        = string
}

variable "image" {
  description = "The container image url/name"
  type        = string
}

variable "image_version" {
  description = "The version of the image to use"
  type        = string
}

variable "container_port" {
  description = "Port of the container to expose"
  type        = number
}

variable "repo_url" {
  description = "The URL of the service's source code"
  type        = string
}

variable "image_pull_secret" {
  description = "The name of the k8s secret with docker credentials needed to pull the image. See https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/ for more details"
  type        = string
  default     = ""
}

variable "container_env" {
  description = "Environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "container_args" {
  description = "Args to run the container with"
  type        = list(string)
  default     = []
}

variable "public_urls" {
  description = "The publicly exposed URLs of the service"
  type        = list(string)
  default     = []
}

variable "ingress_annotations" {
  description = "Annotations to add to the ingress resource. Annotations kubernetes.io/ingress.class, nginx.ingress.kubernetes.io/ssl-redirect, and nginx.ingress.kubernetes.io/force-ssl-redirect are overwritten."
  type        = map(string)
  default     = {}
}

variable "iam_policy_doc" {
  description = "The IAM Policy Document to apply to the code running in this deployment."
  type        = string
  default     = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "*",
      "Effect": "Deny",
      "Resource": "*"
    }
  ]
}
EOT
}

variable "health_check" {
  description = "Enable/Disable health check"
  type        = bool
  default     = true
}

variable "replicas" {
  description = "The number of replicas of the pod to create"
  type        = number
  default     = 1
}

variable "private" {
  description = "Only allow access to this service from the private (10.0.0.0/8) network"
  type        = bool
  default     = false
}

variable "resource_limits" {
  description = "Maximum resources the containers created by this deployment can consume"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = null
    memory = null
  }
}
