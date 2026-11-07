module "static_website" {
  source = "../../modules/static-website"

  app_name    = var.app_name
  environment = "dev"
  location    = var.location
}
