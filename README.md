# `deployment-pipeline`

This module is meant to be used as a remote Terraform module within other services.  See my [pipeline-example](https://github.com/jdhollis/pipeline-example) for a usage example.

```hcl
module "pipeline" {
  source = "github.com/jdhollis/deployment-pipeline"

  github_token = var.github_token
  github_user  = var.github_user

  env_deployer_policy_json = {
    stage = module.stage.json
    prod  = module.prod.json
  }

  region                     = var.region
  remote_state_bucket        = "…"
  remote_state_locking_table = "…"

  required_services = [
    "…"
  ]

  service_name = "…"
}
```

You need to create service-specific deployer policy JSON for each environment.

If the deployer needs access to remote state from other services, you can pass in their keys to `required_services` (e.g., "datomic", "elasticsearch", etc.).
