variable bastion_id {
    default = null
}

variable bastion_type {
    default = "standard"
}

variable bastion_name {
    default = "Bastion"
}
variable compartment_id {}

variable bastion_subnet {}

variable bastion_client_cidr_block_allow_list {
    default = []
}

variable defined_tags {}

variable bastion_max_session_ttl_in_seconds {
    default = 3600 * 24
}