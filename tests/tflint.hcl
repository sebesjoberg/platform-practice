# tflint config used by tests/validate-reference.sh (azurerm ruleset enabled).
plugin "azurerm" {
  enabled = true
  version = "0.29.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
