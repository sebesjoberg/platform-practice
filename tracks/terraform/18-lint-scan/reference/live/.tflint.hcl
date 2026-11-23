# tflint for every stack and module (tf-18). The plan job runs, from the repo root:
#   tflint --init --config "$PWD/.tflint.hcl"
#   tflint --recursive --config "$PWD/.tflint.hcl" --chdir terraform
# Any warning or error fails the job.

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.29.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
