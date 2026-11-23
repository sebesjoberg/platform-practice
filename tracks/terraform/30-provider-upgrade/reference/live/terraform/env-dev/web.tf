# Two web VMs for the Ansible track (tf-25): private only, in the spoke's snet-app. You reach
# them through the jump host. They have no public IP; apt reaches the internet through the
# subnet's default outbound access (see the platform README's cost notes).

module "web" {
  source   = "git::https://github.com/{{GH_OWNER}}/{{MODULES_REPO}}.git//linux-vm?ref=v3.0.0"
  for_each = toset(["1", "2"])

  name                = "vm-${var.prefix}-web-${var.env}-${each.key}"
  resource_group_name = module.spoke.resource_group_name
  location            = var.location
  subnet_id           = module.spoke.subnet_ids["app"]
  ssh_public_key      = var.ssh_public_key

  tags = {
    owner      = var.owner
    env        = var.env
    managed_by = "terraform"
    role       = "web"
  }
}

output "web_private_ips" {
  description = "Private IPs of the web VMs, in name order (reach them through the jump VM)."
  value       = [for k in sort(keys(module.web)) : module.web[k].private_ip_address]
}
