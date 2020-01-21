
variable "env" {
  type        = string
  description = "Account environment (e.g. dev, prd)"
}

variable "vpc_vpn_to_campus" {
  type        = bool
  default     = false
  description = "Retrieve VPC info for the VPC that has VPN access to campus (defaults to false)."
}

variable "department_name" {
  type        = string
  default     = "oit"
  description = "The name of the deparment that owns the account"
}
