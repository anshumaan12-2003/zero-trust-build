variable "subscription_id" {
  description = "The Azure subscription to create everything in."
  type        = string
}

variable "admin_cidr" {
  description = "Your own public IP address as a /32, for example 203.0.113.7/32. Only it can reach SSH and the Kubernetes API."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && endswith(var.admin_cidr, "/32")
    error_message = "admin_cidr must be one address written as a /32, never a range like 0.0.0.0/0."
  }
}

variable "ssh_public_key" {
  description = "The SSH public key to log in with, as one line."
  type        = string
}

variable "budget_email" {
  description = "Where to send the budget alerts."
  type        = string
}

variable "budget_amount" {
  description = "Monthly budget for this resource group, in the subscription's currency."
  type        = number
  default     = 10
}

variable "location" {
  description = "Azure region. Pick one near you that student subscriptions allow."
  type        = string
  default     = "centralindia"
}

variable "vm_size" {
  description = "k3s, Kyverno, Argo CD and Prometheus need about 6 GB together, so the default has 8 GB."
  type        = string
  default     = "Standard_B2ms"
}

variable "k3s_version" {
  description = "The k3s release to install. It matches the Kubernetes minor version that kind uses in CI."
  type        = string
  default     = "v1.35.9+k3s1"
}

variable "prefix" {
  description = "Name prefix for every resource."
  type        = string
  default     = "ztb"
}
