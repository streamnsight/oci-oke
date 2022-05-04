variable "cluster_id" {}

variable "compartment_id" {}

variable "kubernetes_version" {
  default = null
}

variable "ssh_public_key" {
  default = null
}

variable "pool_name" {}

variable "node_shape" {
  default = "VM.Standard.E3.Flex"
}

variable "node_pool_boot_volume_size_in_gbs" {
  default = 50
}

variable "node_ocpus" {
  default = 1
}

variable "node_memory_gb" {
  default = 4
}

variable "node_image_id" {}

variable "nodes_subnet_id" {}

variable "node_pool_initial_node_labels_key" {}

variable "node_pool_initial_node_labels_value" {}

variable "defined_tags" {}