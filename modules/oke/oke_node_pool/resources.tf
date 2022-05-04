resource "tls_private_key" "public_private_key_pair" {
  count     = var.ssh_public_key ? 0 : 1
  algorithm = "RSA"
}

resource "oci_containerengine_node_pool" "oci_oke_node_pool" {
  cluster_id         = var.cluster_id
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version ? var.kubernetes_version : local.latest_kubernetes_version
  name               = var.pool_name ? "${var.node_type} Node Pool" : var.pool_name
  node_shape         = var.node_shape ? var.node_shape : local.shapes[var.node_type][var.node_is_bm][0]

  initial_node_labels {
    key   = var.node_pool_initial_node_labels_key
    value = var.node_pool_initial_node_labels_value
  }

  node_source_details {
    image_id                = var.node_image_id ? var.node_image_id : element([for source in data.oci_containerengine_node_pool_option.oci_oke_node_pool_option.sources : source.image_id if length(regexall("Oracle-Linux-${var.node_linux_version}-20[0-9]*.*", source.source_name)) > 0], 0)
    source_type             = "IMAGE"
    boot_volume_size_in_gbs = var.node_pool_boot_volume_size_in_gbs
  }

  ssh_public_key = var.ssh_public_key ? var.ssh_public_key : tls_private_key.public_private_key_pair[0].public_key_openssh

  node_config_details {
    dynamic "placement_configs" {
      for_each = [for ad in var.availability_domain ? [var.availability_domain] : data.oci_identity_availability_domains.ads.availability_domains : {
        name = ad.name
      }]
      content {
        subnet_id           = var.nodes_subnet_id
        availability_domain = placement_configs.value.name
      }
    }
    size         = var.node_count
    defined_tags = var.defined_tags
  }

  dynamic "node_shape_config" {
    for_each = length(regexall("Flex", var.node_shape)) > 0 ? [1] : []
    content {
      ocpus         = var.node_ocpus
      memory_in_gbs = var.node_memory_gb
    }
  }
  defined_tags = var.defined_tags
}
