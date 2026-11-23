# Plan-only tests for the spoke module. mock_provider fakes azurerm: no credentials, nothing
# reaches Azure, and the tests run anywhere (your laptop, the plan job). command = plan checks
# what Terraform would build from the inputs; computed values such as IDs stay unknown.
# Compare list elements, not lists: ["a"] is a tuple and never equals a list(string).

mock_provider "azurerm" {}

variables {
  env       = "dev"
  vnet_cidr = "10.1.0.0/16"
  prefix    = "acme"
  location  = "swedencentral"
  owner     = "platform-team"

  hub = {
    resource_group_name = "rg-acme-hub"
    vnet_name           = "vnet-acme-hub"
    vnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-hub/providers/Microsoft.Network/virtualNetworks/vnet-acme-hub"
  }

  private_dns_zone_ids = {
    "privatelink.vaultcore.azure.net"   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-hub/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    "privatelink.blob.core.windows.net" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }
}

run "dev_names_and_layout" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.name == "rg-acme-dev" && azurerm_virtual_network.this.name == "vnet-acme-dev"
    error_message = "the spoke must be rg-<prefix>-<env> / vnet-<prefix>-<env>"
  }

  assert {
    condition     = azurerm_resource_group.this.tags["owner"] == "platform-team" && azurerm_resource_group.this.tags["env"] == "dev" && azurerm_resource_group.this.tags["managed_by"] == "terraform"
    error_message = "the resource group needs the owner, env and managed_by tags"
  }

  assert {
    condition     = azurerm_subnet.this["app"].address_prefixes[0] == "10.1.1.0/24" && azurerm_subnet.this["pe"].address_prefixes[0] == "10.1.2.0/24" && azurerm_subnet.this["aca"].address_prefixes[0] == "10.1.4.0/23"
    error_message = "subnets must be app x.1.0/24, pe x.2.0/24 and aca x.4.0/23"
  }

  assert {
    condition     = azurerm_subnet.this["aca"].delegation[0].service_delegation[0].name == "Microsoft.App/environments" && length(azurerm_subnet.this["app"].delegation) == 0
    error_message = "only snet-aca is delegated, to Microsoft.App/environments"
  }

  assert {
    condition     = alltrue([for s in azurerm_subnet.this : s.default_outbound_access_enabled])
    error_message = "every subnet keeps default outbound access, explicitly (the web VMs reach apt through it)"
  }

  assert {
    condition     = length(azurerm_network_security_group.this) == 3 && length(azurerm_subnet_network_security_group_association.this) == 3
    error_message = "every subnet needs its own NSG and association"
  }

  assert {
    condition     = azurerm_virtual_network_peering.hub_to_spoke.name == "peer-hub-to-dev" && azurerm_virtual_network_peering.hub_to_spoke.resource_group_name == "rg-acme-hub" && azurerm_virtual_network_peering.spoke_to_hub.name == "peer-dev-to-hub"
    error_message = "peerings must be peer-hub-to-<env> (in the hub) and peer-<env>-to-hub"
  }

  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.this) == 2 && azurerm_private_dns_zone_virtual_network_link.this["privatelink.blob.core.windows.net"].name == "link-vnet-acme-dev" && endswith(azurerm_private_dns_zone_virtual_network_link.this["privatelink.blob.core.windows.net"].private_dns_zone_id, "/privateDnsZones/privatelink.blob.core.windows.net")
    error_message = "one link-vnet-<prefix>-<env> per private DNS zone, linked by the zone's ID"
  }
}

run "prod_layout" {
  command = plan

  variables {
    env       = "prod"
    vnet_cidr = "10.2.0.0/16"
  }

  assert {
    condition     = azurerm_subnet.this["aca"].address_prefixes[0] == "10.2.4.0/23" && azurerm_network_security_group.this["aca"].name == "nsg-acme-prod-aca"
    error_message = "prod must cut its subnets out of 10.2.0.0/16 and name its NSGs nsg-<prefix>-prod-<subnet>"
  }
}

run "rejects_a_vnet_cidr_that_is_not_a_16" {
  command = plan

  variables {
    vnet_cidr = "10.1.0.0/24"
  }

  expect_failures = [var.vnet_cidr]
}

run "rejects_an_unknown_env" {
  command = plan

  variables {
    env = "test"
  }

  expect_failures = [var.env]
}

run "rejects_a_zone_id_that_does_not_match_its_name" {
  command = plan

  variables {
    private_dns_zone_ids = {
      "privatelink.vaultcore.azure.net" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    }
  }

  expect_failures = [var.private_dns_zone_ids]
}
