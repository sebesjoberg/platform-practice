# tf-15: the spoke resources moved into module "spoke". A moved block renames an address in
# this stack's state, so the plan shows "has moved to" instead of destroy + create. A
# whole-resource move takes every for_each instance with it. Keep these blocks: they are a no-op
# once applied, and they still migrate any state that has the old addresses.

moved {
  from = azurerm_resource_group.spoke
  to   = module.spoke.azurerm_resource_group.this
}

moved {
  from = azurerm_virtual_network.spoke
  to   = module.spoke.azurerm_virtual_network.this
}

moved {
  from = azurerm_subnet.spoke
  to   = module.spoke.azurerm_subnet.this
}

moved {
  from = azurerm_network_security_group.spoke
  to   = module.spoke.azurerm_network_security_group.this
}

moved {
  from = azurerm_subnet_network_security_group_association.spoke
  to   = module.spoke.azurerm_subnet_network_security_group_association.this
}

moved {
  from = azurerm_virtual_network_peering.hub_to_spoke
  to   = module.spoke.azurerm_virtual_network_peering.hub_to_spoke
}

moved {
  from = azurerm_virtual_network_peering.spoke_to_hub
  to   = module.spoke.azurerm_virtual_network_peering.spoke_to_hub
}

moved {
  from = azurerm_private_dns_zone_virtual_network_link.spoke
  to   = module.spoke.azurerm_private_dns_zone_virtual_network_link.this
}
