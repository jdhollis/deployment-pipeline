variable "env_deployer_policy_json" {
  type = map(string)
}

variable "github_token" {}
variable "github_user" {}

variable "region" {}

variable "required_services" {
  type    = list(string)
  default = []
}

variable "repo_name" {
  default = ""
}

variable "remote_state_bucket" {}
variable "remote_state_locking_table" {}
variable "service_name" {}

