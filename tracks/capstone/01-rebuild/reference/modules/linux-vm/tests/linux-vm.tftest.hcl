# Plan-only tests for the linux-vm module. mock_provider fakes azurerm: no credentials, nothing
# reaches Azure.

mock_provider "azurerm" {}

variables {
  name                = "vm-acme-web-dev-1"
  resource_group_name = "rg-acme-dev"
  location            = "swedencentral"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acme-dev/providers/Microsoft.Network/virtualNetworks/vnet-acme-dev/subnets/snet-app"
  # A throwaway key (its private half was deleted): the provider parses public keys even in plans.
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbG5bSUW5X3XwP7w2zy2uRxzooFWF1cNkhrNJ3menoy lab-test"
  tags = {
    role = "web"
    env  = "dev"
  }
}

run "private_web_vm" {
  command = plan

  assert {
    condition     = azurerm_linux_virtual_machine.this.name == "vm-acme-web-dev-1" && azurerm_linux_virtual_machine.this.size == "Standard_B2ats_v2"
    error_message = "the VM takes var.name and defaults to Standard_B2ats_v2"
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this.source_image_reference[0].offer == "ubuntu-24_04-lts" && azurerm_linux_virtual_machine.this.source_image_reference[0].publisher == "Canonical"
    error_message = "the image is Canonical's Ubuntu 24.04 LTS"
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this.disable_password_authentication && length(azurerm_linux_virtual_machine.this.admin_ssh_key) == 1
    error_message = "SSH key only: password authentication off, one admin_ssh_key"
  }

  assert {
    condition     = length(azurerm_public_ip.this) == 0 && azurerm_network_interface.this.ip_configuration[0].public_ip_address_id == null
    error_message = "no public IP unless public_ip_name is set"
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.this.identity) == 0
    error_message = "no identity unless system_assigned_identity = true"
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this.tags["role"] == "web" && azurerm_network_interface.this.name == "vm-acme-web-dev-1-nic"
    error_message = "tags go on the VM; the NIC is <name>-nic"
  }
}

run "jump_with_public_ip_and_identity" {
  command = plan

  variables {
    name                     = "vm-acme-jump"
    public_ip_name           = "pip-acme-jump"
    system_assigned_identity = true
  }

  assert {
    condition     = azurerm_public_ip.this[0].name == "pip-acme-jump" && azurerm_public_ip.this[0].sku == "Standard" && azurerm_public_ip.this[0].allocation_method == "Static"
    error_message = "public_ip_name creates a Standard, static public IP"
  }

  assert {
    condition     = azurerm_linux_virtual_machine.this.identity[0].type == "SystemAssigned"
    error_message = "system_assigned_identity = true gives the VM a system-assigned identity"
  }
}

run "web_vm_with_the_runner_key" {
  command = plan

  variables {
    # A second throwaway key (cap-01: the CI runner's; its private half was deleted too), plus a
    # duplicate of the first, which counts once.
    extra_ssh_public_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbG5bSUW5X3XwP7w2zy2uRxzooFWF1cNkhrNJ3menoy lab-test",
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAvVJi2i3bow4pB1cuhJ7wi2TdNYrPtcuByn5naEepV2 lab-runner",
    ]
  }

  assert {
    condition     = length(azurerm_linux_virtual_machine.this.admin_ssh_key) == 2
    error_message = "extra_ssh_public_keys adds keys for the admin user; a duplicate counts once"
  }

  assert {
    condition     = alltrue([for k in azurerm_linux_virtual_machine.this.admin_ssh_key : k.username == "azureuser"])
    error_message = "every key is for admin_username"
  }
}

run "rejects_a_malformed_extra_key" {
  command = plan

  variables {
    extra_ssh_public_keys = ["not a key"]
  }

  expect_failures = [var.extra_ssh_public_keys]
}

run "rejects_a_password_style_key" {
  command = plan

  variables {
    ssh_public_key = "hunter2"
  }

  expect_failures = [var.ssh_public_key]
}

run "rejects_a_size_outside_the_b_series" {
  command = plan

  variables {
    size = "Standard_D2s_v5"
  }

  expect_failures = [var.size]
}
