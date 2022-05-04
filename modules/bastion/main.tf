resource "oci_bastion_bastion" "bastion" {
    count = var.bastion_id ? 0 : 1
    #Required
    bastion_type = var.bastion_type
    compartment_id = var.compartment_id
    target_subnet_id = var.bastion_subnet_id

    #Optional
    client_cidr_block_allow_list = var.bastion_client_cidr_block_allow_list
    defined_tags = var.defined_tags
    freeform_tags = var.freeform_tags
    max_session_ttl_in_seconds = var.bastion_max_session_ttl_in_seconds
    name = var.bastion_name
}