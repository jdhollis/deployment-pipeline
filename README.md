# deployment-pipeline

This module creates a CodePipeline for deploying a service across multiple AWS accounts.

<img src="diagram.png?raw=true" width="50%" alt="diagram" />

## Usage

This module is meant to be used as a remote Terraform module within other services.

```hcl
module "pipeline" {
  source = "github.com/jdhollis/deployment-pipeline"

  builder_build_timeout  = "…" # Defaults to 15 minutes
  deployer_build_timeout = "…" # Defaults to 15 minutes

  env_deployer_policy_json = {
    stage = module.stage.json
    prod  = module.prod.json
  }

  github_token = var.github_token
  github_user  = var.github_user

  region                     = var.region
  remote_state_bucket        = "…"
  remote_state_locking_table = "…"

  required_services = [
    "…"
  ]

  service_name = "…"
}
```

You need to create service-specific deployer policy JSON for each environment. See my [pipeline-example](https://github.com/jdhollis/pipeline-example), particularly [`service-example/pipeline/env-deployer-policy`](https://github.com/jdhollis/pipeline-example/tree/master/service-example/pipeline/env-deployer-policy).

If the deployer needs access to remote state from other services, you can pass in their keys to `required_services` (e.g., "datomic", "elasticsearch", etc.).
