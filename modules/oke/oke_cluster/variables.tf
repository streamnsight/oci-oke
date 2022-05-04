variable "compartment_ocid" {}

variable "kubernetes_version" {
  default = null
}

variable "oke_cluster_name" {
  default = "OKE Cluster"
}

variable "use_existing_vcn" {
  default = false
}

variable "vcn_native" {
  default = true
}

variable "vcn_ocid" {
  default = null
}

variable "is_api_endpoint_subnet_public" {
  default = false
}

variable "api_endpoint_subnet_id" {
  default = null
}

variable "lb_subnet_id" {
  default = null
}

variable "pods_cidr" {
  default = "10.0.0.10/24"
}

variable "services_cidr" {
  default = "10.0.0.20/24"
}

variable "cluster_image_policy_config_is_policy_enabled" {
  default = false
}

variable "image_policy_key_ocid" {
  default = null
}

variable "secrets_encryption_key_ocid" {
  default = null
}

variable "cluster_options_add_ons_is_kubernetes_dashboard_enabled" {
  default = true
}

variable "cluster_options_add_ons_is_tiller_enabled" {
  default = true
}

variable "cluster_options_admission_controller_options_is_pod_security_policy_enabled" {
  default = false
}

variable "defined_tags" {
  default = null
}