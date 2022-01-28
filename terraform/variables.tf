variable "organization_prefix" {
  description = "The prefix to give to all parameters and log groups for organiztion."
  type        = string
  default     = "teak"
}

variable "domain_root" {
  description = "The root domain (e.g. example.com) that docs should be hosted under."
}

variable "subdomain" {
  description = "The subdomain of var.domain_root that docs should be hosted under."
  type        = string
  default     = "docs"
}

variable "region" {
  description = "The AWS region to deploy all resources to."
  type        = string
  default     = "us-east-1"
}
