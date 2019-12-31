variable "assume_codebuild_service_role_json" {}
variable "build_artifacts_bucket" {}
variable "build_artifacts_key_arn" {}
variable "build_timeout" {}
variable "env_deployer_policy_json" {}
variable "github_user" {}
variable "region" {}

variable "remote_state" {
  type = "map"
}

variable "remote_state_region" {}

variable "required_services" {
  type = list(string)
}

variable "service_name" {}
variable "target_env" {}
variable "tools_remote_state_bucket_arn" {}

output "codebuild_project_name" {
  value = aws_codebuild_project.deployer.name
}
