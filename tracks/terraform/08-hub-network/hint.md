# tf-08 hints

Docs:
- `azurerm_virtual_network`, `azurerm_subnet`, `azurerm_subnet_network_security_group_association`:
  https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association
- `for_each` over a map: https://developer.hashicorp.com/terraform/language/meta-arguments/for_each
- NSG default rules: https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview#default-security-rules
- Hub-spoke topology: https://learn.microsoft.com/azure/architecture/networking/architecture/hub-spoke

Traps:
- **One map, three resources.** A `locals` map `{ shared = "10.0.1.0/24", ... }` drives the
  subnets, the NSGs and the associations with the same `for_each`. Then
  `azurerm_subnet.hub["runner"].id` pairs naturally with
  `azurerm_network_security_group.hub["runner"].id`.
- **Don't mix inline `subnet {}` blocks with `azurerm_subnet` resources** for the same VNet.
  Both manage the subnets, and every plan fights the other. Use separate resources: later tasks
  reference subnet IDs, and tf-14 moves subnets between stacks one by one.
- **`address_prefixes` is a list**, even for one prefix.
- **An empty NSG isn't an open NSG.** Default rule 65500 denies all inbound traffic from the
  internet. Don't add "allow" rules "for later": trivy (tf-18) flags them, and so would any
  security review.
- **Subnet names have no prefix** (`snet-runner`): they only need to be unique inside their
  VNet. NSGs are top-level resources in the group, so their names carry prefix and VNet.
