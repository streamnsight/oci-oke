
data "oci_containerengine_cluster_option" "cluster_options" {
  #Required
  cluster_option_id = "all"

  #Optional
  compartment_id = var.compartment_id
}