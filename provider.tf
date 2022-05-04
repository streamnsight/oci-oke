terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">=4.68.0"
    }
  }
}

provider "oci" {
  #   region               = var.region
  disable_auto_retries = "true"
}
