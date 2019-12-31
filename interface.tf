variable "builder_build_timeout" {
  default = "15" # minutes
}

variable "deployer_build_timeout" {
  default = "15" # minutes
}

variable "env_deployer_policy_json" {
  type = map(string)
}

variable "github_repo_owner" {}
variable "github_token" {}
variable "github_user" {}

variable "region" {}
variable "remote_state_bucket" {}
variable "remote_state_locking_table" {}

variable "repo_name" {
  default = ""
}

variable "required_services" {
  type    = list(string)
  default = []
}

variable "service_name" {}
