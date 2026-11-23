variable "env" {
  type = string
}

variable "address_space" {
  type = string
}

variable "prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "owner" {
  type = string
}

variable "hub" {
  type = object({
    resource_group_name = string
    vnet_name           = string
    vnet_id             = string
  })
}

variable "private_dns_zone_names" {
  type = set(string)
}
