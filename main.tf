provider "aws" {
  version = "~> 2.32"
  region  = var.region
  profile = "ops-tools"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_role" "ops" {
  name = "Ops"
}

data "terraform_remote_state" "remote_state" {
  backend = "s3"

  config = {
    bucket         = var.remote_state_bucket
    key            = "remote-state/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = var.remote_state_locking_table
    profile        = "ops-tools"
  }
}

module "build_artifacts_key" {
  source = "github.com/jdhollis/s3-kms-key"

  principals = [data.aws_iam_role.ops.arn]
  alias_name = "${var.service_name}-build-artifacts-key"
}

resource "aws_s3_bucket" "build_artifacts" {
  bucket = "${var.service_name}-build-artifacts"

  versioning {
    enabled = true
  }
}

data "aws_iam_policy_document" "assume_codebuild_service_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["codebuild.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "builder" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.service_name}-builder",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.service_name}-builder:*",
    ]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
    ]

    resources = ["${aws_s3_bucket.build_artifacts.arn}/*"]
  }

  statement {
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/github/${var.github_user}"]
  }
}

resource "aws_iam_role" "builder" {
  name               = "${var.service_name}-builder"
  assume_role_policy = data.aws_iam_policy_document.assume_codebuild_service_role.json
}

resource "aws_iam_role_policy" "builder" {
  name   = "${var.service_name}-builder"
  role   = aws_iam_role.builder.id
  policy = data.aws_iam_policy_document.builder.json
}

resource "aws_codebuild_project" "builder" {
  name = "${var.service_name}-builder"

  source {
    type = "CODEPIPELINE"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    image        = "aws/codebuild/standard:2.0"
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"

    environment_variable {
      name  = "GITHUB_PK_PARAM_PATH"
      value = "/github/${var.github_user}"
    }
  }

  service_role  = aws_iam_role.builder.arn
  build_timeout = var.builder_build_timeout
}

data "aws_iam_policy_document" "assume_codepipeline_service_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["codepipeline.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "codepipeline_service" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObject",
    ]

    resources = ["${aws_s3_bucket.build_artifacts.arn}/*"]
  }

  statement {
    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "codepipeline_service" {
  name               = "${var.service_name}-codepipeline-service"
  assume_role_policy = data.aws_iam_policy_document.assume_codepipeline_service_role.json
}

resource "aws_iam_role_policy" "codepipeline_service" {
  name   = "${var.service_name}-codepipeline-service"
  role   = aws_iam_role.codepipeline_service.id
  policy = data.aws_iam_policy_document.codepipeline_service.json
}

module "stage_deployer" {
  source = "./deployer"

  assume_codebuild_service_role_json = data.aws_iam_policy_document.assume_codebuild_service_role.json
  build_artifacts_bucket             = aws_s3_bucket.build_artifacts.id
  build_artifacts_key_arn            = module.build_artifacts_key.arn
  build_timeout                      = var.deployer_build_timeout
  env_deployer_policy_json           = var.env_deployer_policy_json["stage"]
  github_user                        = var.github_user
  region                             = var.region
  remote_state                       = data.terraform_remote_state.remote_state.outputs.env.stage
  remote_state_region                = data.terraform_remote_state.remote_state.outputs.region
  required_services                  = var.required_services
  service_name                       = var.service_name
  target_env                         = "stage"
  tools_remote_state_bucket_arn      = data.terraform_remote_state.remote_state.outputs.env.tools.bucket_arn
}

module "prod_deployer" {
  source = "./deployer"

  assume_codebuild_service_role_json = data.aws_iam_policy_document.assume_codebuild_service_role.json
  build_artifacts_bucket             = aws_s3_bucket.build_artifacts.id
  build_artifacts_key_arn            = module.build_artifacts_key.arn
  build_timeout                      = var.deployer_build_timeout
  env_deployer_policy_json           = var.env_deployer_policy_json["prod"]
  github_user                        = var.github_user
  region                             = var.region
  remote_state                       = data.terraform_remote_state.remote_state.outputs.env.prod
  remote_state_region                = data.terraform_remote_state.remote_state.outputs.region
  required_services                  = var.required_services
  service_name                       = var.service_name
  target_env                         = "prod"
  tools_remote_state_bucket_arn      = data.terraform_remote_state.remote_state.outputs.env.tools.bucket_arn
}

resource "aws_codepipeline" "pipeline" {
  name     = var.service_name
  role_arn = aws_iam_role.codepipeline_service.arn

  artifact_store {
    location = aws_s3_bucket.build_artifacts.id
    type     = "S3"

    encryption_key {
      id   = module.build_artifacts_key.arn
      type = "KMS"
    }
  }

  stage {
    name = "Source"

    action {
      category = "Source"
      name     = "Source"
      owner    = "ThirdParty"
      provider = "GitHub"
      version  = "1"

      output_artifacts = ["src"]

      configuration = {
        OAuthToken = var.github_token
        Owner      = var.github_repo_owner
        Repo       = var.repo_name == "" ? var.service_name : var.repo_name
        Branch     = "master"
      }
    }
  }

  stage {
    name = "BuildArtifacts"

    action {
      category = "Build"
      name     = "BuildArtifacts"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts  = ["src"]
      output_artifacts = ["plan"]

      configuration = {
        ProjectName = aws_codebuild_project.builder.name
      }
    }
  }

  stage {
    name = "Plan"

    action {
      category = "Build"
      name     = "PlanForStage"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts  = ["plan"]
      output_artifacts = ["stage-apply"]

      configuration = {
        ProjectName = module.stage_deployer.codebuild_project_name
      }
    }

    action {
      category = "Build"
      name     = "PlanForProd"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts  = ["plan"]
      output_artifacts = ["prod-apply"]

      configuration = {
        ProjectName = module.prod_deployer.codebuild_project_name
      }
    }
  }

  stage {
    name = "ApplyToStage"

    action {
      category = "Build"
      name     = "ApplyToStage"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts = ["stage-apply"]

      configuration = {
        ProjectName = module.stage_deployer.codebuild_project_name
      }
    }
  }

  stage {
    name = "Approve"

    action {
      category = "Approval"
      name     = "Approve"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
    }
  }

  stage {
    name = "ApplyToProd"

    action {
      category = "Build"
      name     = "ApplyToProd"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts = ["prod-apply"]

      configuration = {
        ProjectName = module.prod_deployer.codebuild_project_name
      }
    }
  }
}
