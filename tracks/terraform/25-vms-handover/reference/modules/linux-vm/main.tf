# One Linux VM: Ubuntu 24.04 LTS, SSH key only, one NIC, optionally a public IP and a
# system-assigned identity. Configuration management happens after boot (the Ansible track);
# the module sets up nothing inside the VM.

resource "azurerm_public_ip" "this" {
  count = var.public_ip_name == null ? 0 : 1

  name                = var.public_ip_name
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "this" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = try(azurerm_public_ip.this[0].id, null)
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.size
  tags                = var.tags

  network_interface_ids = [azurerm_network_interface.this.id]

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = trimspace(var.ssh_public_key)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS" # the cheapest managed disk; a lab VM needs no SSD
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  dynamic "identity" {
    for_each = var.system_assigned_identity ? [1] : []

    content {
      type = "SystemAssigned"
    }
  }
}
