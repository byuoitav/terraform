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

variable "public_url" {
  description = "The publicly exposed URL of the service"
  type        = string
  default     = ""
}
