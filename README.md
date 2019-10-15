# `deployment-pipeline`

This module is meant to be used as a remote Terraform module within other services.

```hcl
module "pipeline" {
  source = "github.com/jdhollis/deployment-pipeline"

  env_deployer_policy_json = {
    stage = module.stage.json
    prod  = module.prod.json
  }

  region = var.region

  required_services = [
    "…"
  ]

  service_name = "…"
  github_token = var.github_token
}
```

You need to create service-specific deployer policy JSON for each environment.

If the deployer needs access to remote state from other services, you can pass in their keys to `required_services` (e.g., "datomic", "elasticsearch", etc.).
