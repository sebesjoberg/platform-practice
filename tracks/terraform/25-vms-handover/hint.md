# tf-25 hints

Docs:
- `azurerm_linux_virtual_machine`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine
- `azurerm_network_security_rule`: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule
- Find Ubuntu images: https://learn.microsoft.com/azure/virtual-machines/linux/cli-ps-findimage
- Default outbound access (how private VMs reach the internet): https://learn.microsoft.com/azure/virtual-network/ip-services/default-outbound-access

Traps:
- **Which stack owns the SSH rule?** The NSG belongs to landing-zone, but the rule belongs to
  the jump VM: put it in `shared`, as a standalone `azurerm_network_security_rule`. Then
  `./lab.sh pause` closes port 22 together with the VM. This works because landing-zone's NSG
  has no inline `security_rule` blocks; mixing inline rules and rule resources on one NSG makes
  them overwrite each other.
- **Secret and sensitive: two different leaks.** The repo secret keeps your IP out of the run
  logs (GitHub prints `env:` values in every step log of a public repo and masks only secrets).
  `sensitive = true` keeps it out of the public PR plan comment (`(sensitive value)`). It's still
  in the state, which is fine: the state is private.
- **Why two PRs?** The plan job plans every stack on the PR before anything is applied. A
  `data "azurerm_virtual_machine"` in the env stacks would look for a jump VM that only the same
  PR creates; the plan fails, and `plan` is the required check. So PR 1 builds the VMs, PR 2
  grants the vault access. (tf-22 could avoid that by building the registry's ID from names; a
  VM's principal ID only exists once the VM does.) The same applies while the lab is paused: a
  PR planned then fails in the env stacks until `./lab.sh resume` brings the jump VM back.
- **The image.** Ubuntu 24.04's offer is `ubuntu-24_04-lts` with sku `server` (Gen2), not the
  `0001-com-ubuntu-…` offers of older releases. `az vm image list -p Canonical -f ubuntu-24_04-lts --all -o table`
  lists them.
- **SSH keys.** `ssh-ed25519` and `ssh-rsa` (2048 bits or more) work. The provider parses the
  key, so a placeholder string fails even in a plan (and in `terraform test`).
- **Who grants Key Vault access to the jump VM?** `shared` runs before the env stacks, so it
  can't reference vaults that don't exist yet on a fresh build. Each env stack finds the VM
  (`data "azurerm_virtual_machine"`, `identity[0].principal_id`) and grants access to its own
  vault, the same "consumer side" pattern as `AcrPull`, turned around: the owner of the vault
  decides who reads it.
- **How do the web VMs reach apt without a public IP?** The spoke's subnets use Azure's default
  outbound access (the azurerm provider creates subnets with
  `default_outbound_access_enabled = true`). Azure is retiring it for new VNets, but a subnet can
  still opt in, and it's free. A NAT gateway is the production answer, and would cost more than
  all three VMs together.
- **`-J` and keys.** `ssh -J` doesn't pass `-i` to the jump hop. Use `~/.ssh/config` with
  `IdentityFile` for both hosts, or a `ProxyCommand` that carries the key.
- **Plan comment vs apply log.** The public IP shows up in the apply log (an output). That's
  expected: port 22 is open to your IP only.
