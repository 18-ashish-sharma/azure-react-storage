# azure-react-storage

[![terraform](https://github.com/18-ashish-sharma/azure-react-storage/actions/workflows/terraform.yml/badge.svg)](https://github.com/18-ashish-sharma/azure-react-storage/actions/workflows/terraform.yml)
[![app](https://github.com/18-ashish-sharma/azure-react-storage/actions/workflows/app.yml/badge.svg)](https://github.com/18-ashish-sharma/azure-react-storage/actions/workflows/app.yml)
![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.6-7B42BC?logo=terraform)
![azurerm](https://img.shields.io/badge/azurerm-~%3E4.0-0078D4?logo=microsoftazure)
![React](https://img.shields.io/badge/react-18-61DAFB?logo=react)

Terraform that hosts a React single-page app (Vite + TypeScript) as an **Azure Storage static
website**: HTTPS only, TLS 1.2 minimum, no anonymous blob access, soft delete for rollback.
GitHub Actions checks every change without cloud credentials and deploys with **OIDC**; the
build is uploaded with **Entra ID** (`--auth-mode login`), not an account key.

## Architecture

```mermaid
flowchart LR
  U[Browser] -- HTTPS only, TLS 1.2+ --> WEB[Static website endpoint<br/>https://ACCOUNT.zN.web.core.windows.net]
  subgraph RG[Resource group rg-reactapp-dev]
    SA[(Storage account StorageV2<br/>$web container<br/>soft delete 7 days)]
  end
  WEB --> SA
  subgraph GH[GitHub Actions]
    D[deploy.yml]
  end
  D -- OIDC token --> E[Microsoft Entra ID<br/>federated credential]
  E -- access token --> TF[Terraform]
  TF -- state + blob lease lock --> ST[(Storage account<br/>tfstate)]
  TF --> RG
  D -- az storage blob upload-batch<br/>--auth-mode login --> SA
```

- `index.html` is uploaded with `Cache-Control: no-cache`; Vite's hashed files in `assets/`
  get a one-year `immutable` cache, so a new deploy shows up at once.
- `error_404_document = "index.html"`: a deep link such as `/about` returns the app, and the
  client-side router renders the page. (Azure still sends status 404 for such paths; put
  Azure Front Door in front if a 200 matters, for example for SEO.)

## Repository layout

```
.
├── webapp/                         React 18 + TypeScript, built with Vite into webapp/dist
├── terraform/
│   ├── modules/static-website/     Resource group, storage account, static website, upload role
│   └── environments/
│       └── dev/                    Root module: provider, azurerm backend, module call
├── .tflint.hcl                     tflint + azurerm ruleset
└── .github/workflows/
    ├── terraform.yml               fmt, validate, tflint, checkov (PR + main, no credentials)
    ├── app.yml                     npm ci, type-check, build (PR + main)
    └── deploy.yml                  Manual: build -> plan -> approval -> apply -> upload -> smoke test (OIDC)
```

A new environment is a copy of `environments/dev` with its own state key, so a `plan` in one
environment can never touch another.

## Prerequisites

- Terraform >= 1.6, Azure CLI, Node.js 20
- An Azure subscription where you can create resources **and role assignments** (Owner, or
  Contributor + Role Based Access Control Administrator), because the module gives the
  identity running Terraform *Storage Blob Data Contributor* on the site's account
- A storage account for remote state (one-time):

```bash
az group create -n rg-tfstate -l centralindia
az storage account create -n <unique-name> -g rg-tfstate --sku Standard_LRS \
  --min-tls-version TLS1_2 --allow-blob-public-access false
az storage container create -n tfstate --account-name <unique-name> --auth-mode login
# Your user / the CI identity needs "Storage Blob Data Contributor" on this account.
```

## Run locally

```bash
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)   # azurerm 4.x needs it

cd terraform/environments/dev
cp backend.hcl.example backend.hcl        # set storage_account_name
cp example.tfvars dev.tfvars              # both copies are git-ignored

terraform init -backend-config=backend.hcl
terraform plan  -var-file=dev.tfvars -out=tfplan
terraform apply tfplan

# Build and upload the app (role assignments can take a few minutes to apply on the first run)
cd ../../../webapp && npm ci && npm run build
ACCOUNT=$(terraform -chdir=../terraform/environments/dev output -raw storage_account_name)
az storage blob upload-batch --auth-mode login --account-name "$ACCOUNT" \
  --destination '$web' --source dist --overwrite
open "$(terraform -chdir=../terraform/environments/dev output -raw website_url)"
```

Run the app on your machine: `cd webapp && npm ci && npm run dev`.
`terraform destroy` in `environments/dev` removes everything.

## CI/CD

| Workflow | Trigger | Credentials | What it does |
|---|---|---|---|
| `terraform.yml` | PR, push to `main` | none | `fmt -check`, `init -backend=false` + `validate` for the module and the root, `tflint`, `checkov` (SARIF to the Security tab) |
| `app.yml` | PR, push to `main` | none | `npm ci`, `tsc --noEmit`, `vite build`, uploads `dist/` |
| `deploy.yml` | manual (`workflow_dispatch`) | OIDC | build -> `terraform plan` (saved plan) -> **approval** on the `dev` GitHub environment -> `apply` that exact plan -> upload to `$web` -> smoke test |

### One-time OIDC setup

GitHub issues a short-lived token per job; Entra ID trusts it through a federated
credential, so there is no client secret to store or rotate.

```bash
APP_ID=$(az ad app create --display-name gh-azure-react-storage --query appId -o tsv)
az ad sp create --id "$APP_ID"
SUB=$(az account show --query id -o tsv)
REPO=18-ashish-sharma/azure-react-storage

# Permissions: create resources + the role assignment the module makes.
az role assignment create --assignee "$APP_ID" --role Contributor --scope "/subscriptions/$SUB"
az role assignment create --assignee "$APP_ID" --role "Role Based Access Control Administrator" \
  --scope "/subscriptions/$SUB"
az role assignment create --assignee "$APP_ID" --role "Storage Blob Data Contributor" \
  --scope "$(az storage account show -n <unique-name> -g rg-tfstate --query id -o tsv)"

# The plan job runs on main without an environment; the apply job runs in the 'dev'
# environment. The token subject differs, so each needs its own federated credential.
az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\": \"main\", \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:$REPO:ref:refs/heads/main\", \"audiences\": [\"api://AzureADTokenExchange\"]}"
az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\": \"env-dev\", \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:$REPO:environment:dev\", \"audiences\": [\"api://AzureADTokenExchange\"]}"
```

In GitHub:

- **Repository secrets**: `AZURE_CLIENT_ID` (= `$APP_ID`), `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
- **Repository variables**: `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`
- **Environment** `dev`: add required reviewers and limit deployment branches to `main`

`deploy.yml` fails until this is done; `terraform.yml` and `app.yml` need nothing.

## Security notes

- **No secrets in the repo or in CI.** GitHub -> Azure uses OIDC instead of a client secret.
  The build is uploaded with Entra ID and *Storage Blob Data Contributor* on this one account,
  not with a connection string. `*.tfvars`, `backend.hcl` and state are git-ignored, and no
  Terraform output contains a key.
- **Transport**: HTTPS only (HTTP requests are refused), TLS 1.2 minimum.
- **Access**: anonymous blob access is off; the site is served by the static website endpoint,
  which does not need it. SFTP local users are off. Any SAS token is limited to one day.
- **Encryption and recovery**: infrastructure (double) encryption; blob and container soft
  delete for 7 days.
- **Shared key access is still enabled** because the azurerm provider configures the static
  website through the data plane with the account key. Next step: `storage_use_azuread = true`
  in the provider and `shared_access_key_enabled = false`.
- Checkov findings that do not apply are skipped inline, each with its reason, next to the
  resource (public network access and private endpoint, which a public website cannot use;
  geo-replication; customer-managed keys; queue logging).

## Cost notes

For a low-traffic site this costs cents a month. Check the Azure pricing calculator for current prices.

| Resource | Cost driver |
|---|---|
| Storage account (Standard, LRS, Hot) | A few hundred KB stored, plus read operations and outbound data transfer |
| Static website endpoint | No extra charge beyond storage operations and egress |
| State storage account | A few KB of state |

Soft-deleted blobs are billed like normal blobs for the 7-day retention. Azure Front Door
(custom domain, WAF, global cache) is the first production addition and the first real cost.

## Credits

The original version of this repo started from Adrian Hall's MIT-licensed
`parcel-typescript-template` (Parcel, Storybook and an npm-scripted Terraform deploy). The
current web app, Terraform and pipelines replace that code.

## Module reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.deployer_blob_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_account.web](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_account_static_website.web](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account_static_website) | resource |
| [random_string.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_app_name"></a> [app\_name](#input\_app\_name) | Short application name used in resource names (lowercase letters and digits, 3-10 chars, because storage account names allow nothing else). | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region for all resources. | `string` | `"centralindia"` | no |
| <a name="input_replication_type"></a> [replication\_type](#input\_replication\_type) | Storage redundancy: LRS (one datacentre), ZRS (three zones), GRS or RAGRS (paired region). | `string` | `"LRS"` | no |
| <a name="input_soft_delete_retention_days"></a> [soft\_delete\_retention\_days](#input\_soft\_delete\_retention\_days) | Days a deleted or overwritten blob or container can still be recovered (1-365). | `number` | `7` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags merged onto the default tags (app, environment, managed\_by). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Resource group holding every resource of this environment. |
| <a name="output_storage_account_name"></a> [storage\_account\_name](#output\_storage\_account\_name) | Storage account hosting the site (upload target for the build). |
| <a name="output_website_url"></a> [website\_url](#output\_website\_url) | HTTPS URL of the static website. |
<!-- END_TF_DOCS -->
