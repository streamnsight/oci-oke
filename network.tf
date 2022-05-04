# ## Copyright © 2021, Oracle and/or its affiliates. 
# ## All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl

locals {
  subnet_cidrs = cidrsubnets(var.vcn_cidr, 12, 8, 8, 4, 4, 4) # API + 2 LB + 3 node pools
}

locals {
  api_subnet_cidr         = element(local.subnet_cidrs, 0)
  public_lb_subnet_cidr   = element(local.subnet_cidrs, 1)
  private_lb_subnet_cidr  = element(local.subnet_cidrs, 2)
  lb_subnets_cidrs        = [for k, v in zipmap(slice(local.subnet_cidrs, 1, 3), [var.allow_deploy_public_lb, var.allow_deploy_private_lb]) : k if v]
  node_pool_subnets_cidrs = slice(local.subnet_cidrs, 3, 6)
}

locals {
  ADs = data.oci_identity_availability_domains.ADs.availability_domains.*.name
}

resource "oci_core_vcn" "oke_vcn" {
  count          = var.use_existing_vcn ? 0 : 1
  cidr_blocks    = [var.vcn_cidr]
  compartment_id = var.vcn_compartment_id
  display_name   = "OKE VCN"
  defined_tags   = var.vcn_tags
}

resource "oci_core_service_gateway" "oke_sg" {
  count          = var.use_existing_vcn ? 0 : 1
  compartment_id = var.vcn_compartment_id
  display_name   = "Service Gateway for OKE VCN"
  vcn_id         = oci_core_vcn.oke_vcn[0].id
  services {
    service_id = lookup(data.oci_core_services.all_oci_services[0].services[0], "id")
  }
  defined_tags = var.vcn_tags
}

resource "oci_core_nat_gateway" "oke_natgw" {
  count          = var.use_existing_vcn ? 0 : 1
  compartment_id = var.vcn_compartment_id
  display_name   = "NAT Gateway for OKE VCN"
  vcn_id         = oci_core_vcn.oke_vcn[0].id
  defined_tags   = var.vcn_tags
}

resource "oci_core_route_table" "oke_rt_via_natgw_and_sg" {
  count          = var.use_existing_vcn ? 0 : 1
  compartment_id = var.vcn_compartment_id
  vcn_id         = oci_core_vcn.oke_vcn[0].id
  display_name   = "via NAT Gateway"
  defined_tags   = var.vcn_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.oke_natgw[0].id
  }

  route_rules {
    destination       = lookup(data.oci_core_services.all_oci_services[0].services[0], "cidr_block")
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.oke_sg[0].id
  }
}

resource "oci_core_internet_gateway" "oke_igw" {
  count          = var.use_existing_vcn ? 0 : 1
  compartment_id = var.vcn_compartment_id
  display_name   = "Internet Gateway for OKE VCN"
  vcn_id         = oci_core_vcn.oke_vcn[0].id
  defined_tags   = var.vcn_tags
}

resource "oci_core_route_table" "oke_rt_via_igw" {
  count          = var.use_existing_vcn ? 0 : 1
  compartment_id = var.vcn_compartment_id
  vcn_id         = oci_core_vcn.oke_vcn[0].id
  display_name   = "via Internet Gateway"
  defined_tags   = var.vcn_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.oke_igw[0].id
  }
}

### Security Lists

resource "oci_core_security_list" "oke_api_endpoint_external_sec_list" {
  count          = var.use_existing_vcn ? 0 : 1
  compartment_id = var.vcn_compartment_id
  display_name   = "API Endpoint External Comm"
  vcn_id         = oci_core_vcn.oke_vcn[0].id
  defined_tags   = var.vcn_tags

  # TCP SSL to Services
  egress_security_rules {
    description      = "Allow Kubernetes control plane to communicate with OKE"
    protocol         = "6"
    destination_type = "SERVICE_CIDR_BLOCK"
    destination      = lookup(data.oci_core_services.all_oci_services[0].services[0], "cidr_block")
    stateless        = false

    tcp_options {
      min = 443
      max = 443
    }
  }

  # Incoming from outside to Endpoint 6443
  ingress_security_rules {
    description = "Client access to Kubernetes API endpoint"
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    stateless   = false

    tcp_options {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_security_list" "oke_api_endpoint_nodes_sec_list" {
  count          = var.use_existing_vcn ? 0 : length([for x in [true, var.np2_create_new_subnet, var.np3_create_new_subnet] : x if x])
  compartment_id = var.vcn_compartment_id
  display_name   = "API Endpoint - Node Pool ${count.index + 1} Comm"
  vcn_id         = oci_core_vcn.oke_vcn[0].id
  defined_tags   = var.vcn_tags

  # TCP All to Nodes
  egress_security_rules {
    description      = "TCP traffic to worker nodes"
    protocol         = "6" # TCP
    destination_type = "CIDR_BLOCK"
    destination      = local.node_pool_subnets_cidrs[count.index]
    stateless        = false
  }

  # ICMP 3,4 to Nodes
  egress_security_rules {
    description      = "Path Discovery."
    protocol         = "1" # ICMP
    destination_type = "CIDR_BLOCK"
    destination      = local.node_pool_subnets_cidrs[count.index]
    stateless        = false

    icmp_options {
      type = 3
      code = 4
    }
  }

  # Incoming ICMP from Nodes
  ingress_security_rules {
    description = "Path Discovery"
    protocol    = "1" # ICMP
    source      = local.node_pool_subnets_cidrs[count.index]
    stateless   = false

    icmp_options {
      type = 3
      code = 4
    }
  }

  # Incoming TCP 6443 from Nodes
  ingress_security_rules {
    description = "Kubernetes worker to Kubernetes API endpoint communication"
    protocol    = "6" # TCP
    source      = local.node_pool_subnets_cidrs[count.index]
    stateless   = false

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Incoming TCP 12250 from Nodes
  ingress_security_rules {
    description = "Kubernetes worker to control plane communication"
    protocol    = "6" # TCP
    source      = local.node_pool_subnets_cidrs[count.index]
    stateless   = false

    tcp_options {
      min = 12250
      max = 12250
    }
  }
}

resource "oci_core_security_list" "oke_nodepool_internal_sec_list" {
  count          = var.use_existing_vcn ? 0 : 1
  compartment_id = var.vcn_compartment_id
  display_name   = "Nodepool - Internal Comm"
  vcn_id         = oci_core_vcn.oke_vcn[0].id
  defined_tags   = var.vcn_tags

  dynamic "egress_security_rules" {
    iterator = cidr
    for_each = local.node_pool_subnets_cidrs
    content {
      description      = "Allow pods on one worker node to communicate with pods on other worker nodes"
      protocol         = "All"
      destination_type = "CIDR_BLOCK"
      destination      = cidr.value
      stateless        = false
    }
  }

  dynamic "ingress_security_rules" {
    iterator = cidr
    for_each = local.node_pool_subnets_cidrs
    content {
      description = "Node to Node"
      protocol    = "All"
      source      = cidr.value
      stateless   = false
    }
  }
}

resource "oci_core_security_list" "oke_nodepool_api_comm_sec_list" {
  count          = var.use_existing_vcn ? 0 : 1
  compartment_id = var.vcn_compartment_id
  display_name   = "Nodepool - API Comm"
  vcn_id         = oci_core_vcn.oke_vcn[0].id
  defined_tags   = var.vcn_tags

  egress_security_rules {
    description      = "Allow nodes to communicate with OKE"
    protocol         = "6"
    destination_type = "SERVICE_CIDR_BLOCK"
    destination      = lookup(data.oci_core_services.all_oci_services[0].services[0], "cidr_block")
    stateless        = false
  }

  egress_security_rules {
    description      = "Kubernetes worker to Kubernetes API endpoint communication"
    protocol         = "6"
    destination_type = "CIDR_BLOCK"
    destination      = local.api_subnet_cidr
    stateless        = false

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  egress_security_rules {
    description      = "Kubernetes worker to control plane communication"
    protocol         = "6"
    destination_type = "CIDR_BLOCK"
    destination      = local.api_subnet_cidr
    stateless        = false

    tcp_options {
      min = 12250
      max = 12250
    }
  }

  ingress_security_rules {
    description = "Allow Kubernetes control plane to communicate with worker nodes"
    protocol    = "6"
    source      = local.api_subnet_cidr
    stateless   = false
  }
}

resource "oci_core_security_list" "oke_nodepool_external_comm_sec_list" {
  count          = var.use_existing_vcn ? 0 : 1
  compartment_id = var.vcn_compartment_id
  display_name   = "Nodepool External Comm"
  vcn_id         = oci_core_vcn.oke_vcn[0].id
  defined_tags   = var.vcn_tags

  # ICMP out
  egress_security_rules {
    description = "Path Discovery."
    protocol    = 1
    destination = "0.0.0.0/0"
    stateless   = false

    icmp_options {
      type = 3
      code = 4
    }
  }

  # Internet access
  egress_security_rules {
    description      = "Allow worker nodes to communicate with internet"
    protocol         = "6"
    destination_type = "CIDR_BLOCK"
    destination      = "0.0.0.0/0"
    stateless        = false
  }

  # ICMP
  ingress_security_rules {
    description = "Path Discovery"
    protocol    = 1
    source      = "0.0.0.0/0"
    stateless   = false

    icmp_options {
      type = 3
      code = 4
    }
  }

  # SSH
  ingress_security_rules {
    description = "Allow inbound SSH traffic to worker nodes"
    protocol    = "6"
    source      = "0.0.0.0/0"
    stateless   = false

    tcp_options {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_security_list" "oke_nodepool_lb_comm_sec_list" {
  count          = var.use_existing_vcn ? 0 : 1
  compartment_id = var.vcn_compartment_id
  display_name   = "Nodepool - Load Balancer Comm"
  vcn_id         = oci_core_vcn.oke_vcn[0].id
  defined_tags   = var.vcn_tags

  dynamic "egress_security_rules" {
    iterator = cidr
    for_each = local.lb_subnets_cidrs
    content {
      description      = "TCP to LBs"
      protocol         = "6"
      destination_type = "CIDR_BLOCK"
      destination      = cidr.value
      stateless        = false
    }
  }

  dynamic "ingress_security_rules" {
    iterator = cidr
    for_each = local.lb_subnets_cidrs
    content {
      description = "TCP from LBs"
      protocol    = "6"
      source      = cidr.value
      stateless   = false
    }
  }
}

resource "oci_core_subnet" "oke_api_endpoint_subnet" {
  count          = var.use_existing_vcn ? 0 : 1
  cidr_block     = local.api_subnet_cidr
  compartment_id = var.vcn_compartment_id
  vcn_id         = oci_core_vcn.oke_vcn[0].id
  display_name   = "API Endpoint Subnet"
  security_list_ids = flatten([
    [oci_core_vcn.oke_vcn[0].default_security_list_id],
    [oci_core_security_list.oke_api_endpoint_external_sec_list[0].id],
    oci_core_security_list.oke_api_endpoint_nodes_sec_list.*.id
  ])
  route_table_id             = var.is_endpoint_public ? oci_core_route_table.oke_rt_via_igw[0].id : oci_core_route_table.oke_rt_via_natgw_and_sg[0].id
  prohibit_public_ip_on_vnic = var.is_endpoint_public ? false : true
  defined_tags               = var.vcn_tags
}

resource "oci_core_subnet" "oke_private_lb_subnet" {
  # if no private lb, count=0, if private lb is enabled and no other, than we can use a regional subnet, 
  # otherwise we need to create AD specific subnets
  count               = (var.use_existing_vcn && !var.allow_deploy_private_lb) ? 0 : 1 #(var.allow_deploy_public_lb ? length(local.ADs) : 1)
  cidr_block          = local.private_lb_subnet_cidr
  compartment_id      = var.vcn_compartment_id
  availability_domain = var.allow_deploy_public_lb ? local.ADs[0] : null
  vcn_id              = oci_core_vcn.oke_vcn[0].id
  display_name        = "Services Private LBs Subnet"

  security_list_ids          = [oci_core_vcn.oke_vcn[0].default_security_list_id]
  route_table_id             = oci_core_route_table.oke_rt_via_natgw_and_sg[0].id
  prohibit_public_ip_on_vnic = true
  defined_tags               = var.vcn_tags
}

resource "oci_core_subnet" "oke_public_lb_subnet" {
  count               = (var.use_existing_vcn && !var.allow_deploy_public_lb) ? 0 : 1 # (var.allow_deploy_private_lb ? length(local.ADs) : 1)
  cidr_block          = local.public_lb_subnet_cidr
  compartment_id      = var.vcn_compartment_id
  availability_domain = var.allow_deploy_private_lb ? local.ADs[0] : null
  vcn_id              = oci_core_vcn.oke_vcn[0].id
  display_name        = "Services Public LBs Subnet"

  security_list_ids          = [oci_core_vcn.oke_vcn[0].default_security_list_id]
  route_table_id             = oci_core_route_table.oke_rt_via_igw[0].id
  prohibit_public_ip_on_vnic = false
  defined_tags               = var.vcn_tags
}

resource "oci_core_subnet" "oke_nodepool_subnet" {
  count          = (var.use_existing_vcn && var.node_pool_count == 0) ? 0 : length([for x in [true, var.np2_create_new_subnet, var.np3_create_new_subnet] : x if x])
  cidr_block     = local.node_pool_subnets_cidrs[count.index]
  compartment_id = var.vcn_compartment_id
  vcn_id         = oci_core_vcn.oke_vcn[0].id
  display_name   = "Node Pool ${count.index + 1} Subnet"

  security_list_ids = [
    oci_core_vcn.oke_vcn[0].default_security_list_id,
    oci_core_security_list.oke_nodepool_lb_comm_sec_list[0].id,
    oci_core_security_list.oke_nodepool_external_comm_sec_list[0].id,
    oci_core_security_list.oke_nodepool_api_comm_sec_list[0].id,
    oci_core_security_list.oke_nodepool_internal_sec_list[0].id
  ]
  route_table_id             = oci_core_route_table.oke_rt_via_natgw_and_sg[0].id
  prohibit_public_ip_on_vnic = true
  defined_tags               = var.vcn_tags
}
