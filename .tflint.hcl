config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.31.1"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# prevent_destroy cannot be driven by a variable, and dev must be destroyable.
# The account holds only a build that is reproducible from git, and blob soft
# delete covers accidental deletes of the files themselves.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
