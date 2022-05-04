
data "oci_containerengine_node_pool_option" "node_pool_options" {
  node_pool_option_id = "all"
}


locals {
  sources = {
    gpu = [for s in data.oci_containerengine_node_pool_option.node_pool_options.sources : s if length(regexall(".*Gen2-GPU.*", s.source_name)) > 0]
    arm = [for s in data.oci_containerengine_node_pool_option.node_pool_options.sources : s if length(regexall(".*aarch64.*", s.source_name)) > 0]
    x86 = [for s in data.oci_containerengine_node_pool_option.node_pool_options.sources : s if length(regexall(".*(aarch64|Gen2-GPU).*", s.source_name)) == 0]
  }
  shapes = {
    gpu = {
      BM = [for s in data.oci_containerengine_node_pool_option.node_pool_options.shapes : s if length(regexall("BM[.]GPU.*", s)) > 0]
      VM = [for s in data.oci_containerengine_node_pool_option.node_pool_options.shapes : s if length(regexall("VM[.]GPU.*", s)) > 0]
    }
    arm = {
      BM = [for s in data.oci_containerengine_node_pool_option.node_pool_options.shapes : s if length(regexall("BM[.]Standard[.]A1.*", s)) > 0]
      VM = [for s in data.oci_containerengine_node_pool_option.node_pool_options.shapes : s if length(regexall("VM[.]Standard[.]A1.*", s)) > 0]
    }
    x86 = {
      BM = [for s in data.oci_containerengine_node_pool_option.node_pool_options.shapes : s if length(regexall(".*(GPU|A1).*", s)) == 0 && length(regexall("BM.*", s)) > 0]
      VM = [for s in data.oci_containerengine_node_pool_option.node_pool_options.shapes : s if length(regexall(".*(GPU|A1).*", s)) == 0 && length(regexall("VM.*", s)) > 0]
    }
  }
  kubernetes_versions       = reverse(data.oci_containerengine_node_pool_option.node_pool_options.kubernetes_versions)
  latest_kubernetes_version = element(reverse(data.oci_containerengine_node_pool_option.node_pool_options.kubernetes_versions), 0)
}

