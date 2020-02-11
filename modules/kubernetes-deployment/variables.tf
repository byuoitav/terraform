variable "name" {
  description = "The name of the service"
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
  description = ""
  type        = string
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
