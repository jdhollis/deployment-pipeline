provider "aws" {
  alias   = "env"
  version = "~> 2.32"
  region  = var.region
  profile = "ops-${var.target_env}"
}

data "aws_caller_identity" "tools" {}
data "aws_region" "tools" {}

data "aws_caller_identity" "env" {
  provider = aws.env
}

data "aws_region" "env" {
  provider = aws.env
}

data "aws_iam_role" "env_ops" {
  provider = aws.env
  name     = "Ops"
}

data "aws_iam_policy_document" "tools_deployer" {
  statement {
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.env_deployer.arn]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.tools.name}:${data.aws_caller_identity.tools.account_id}:log-group:/aws/codebuild/${var.service_name}-${var.target_env}-deployer",
      "arn:aws:logs:${data.aws_region.tools.name}:${data.aws_caller_identity.tools.account_id}:log-group:/aws/codebuild/${var.service_name}-${var.target_env}-deployer:*",
    ]
  }

  statement {
    actions = ["s3:ListBucket"]

    resources = [
      var.remote_state.bucket_arn,
      var.tools_remote_state_bucket_arn,
    ]
  }

  statement {
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
    ]

    resources = ["${var.remote_state.bucket_arn}/${var.service_name}/terraform.tfstate"]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]

    resources = concat(
      formatlist(
        "%s/%s/terraform.tfstate",
        var.tools_remote_state_bucket_arn,
        var.required_services
      ),
      ["arn:aws:s3:::${var.build_artifacts_bucket}/*"]
    )
  }

  statement {
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.build_artifacts_bucket}/*"]
  }

  statement {
    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
    ]

    resources = [var.remote_state.locking_table_arn]
  }

  statement {
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeRegions",
    ]

    resources = ["*"]
  }

  statement {
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${data.aws_region.tools.name}:${data.aws_caller_identity.tools.account_id}:parameter/github/${var.github_user}"]
  }
}

resource "aws_iam_role" "tools_deployer" {
  name               = "${var.service_name}-${var.target_env}-deployer"
  assume_role_policy = var.assume_codebuild_service_role_json
}

resource "aws_iam_role_policy" "tools_deployer" {
  name   = "${var.service_name}-${var.target_env}-deployer"
  role   = aws_iam_role.tools_deployer.id
  policy = data.aws_iam_policy_document.tools_deployer.json
}

data "aws_iam_policy_document" "assume_env_deployer" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = [aws_iam_role.tools_deployer.arn]
      type        = "AWS"
    }
  }
}

resource "aws_iam_role" "env_deployer" {
  provider           = aws.env
  name               = "${var.service_name}-deployer"
  assume_role_policy = data.aws_iam_policy_document.assume_env_deployer.json
}

resource "aws_iam_role_policy" "env_deployer" {
  provider = aws.env
  name     = "${var.service_name}-deployer"
  role     = aws_iam_role.env_deployer.id
  policy   = var.env_deployer_policy_json
}

resource "aws_codebuild_project" "deployer" {
  name = "${var.service_name}-${var.target_env}-deployer"

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
      name  = "ASSUME_ROLE_ARN"
      value = aws_iam_role.env_deployer.arn
    }

    environment_variable {
      name  = "GITHUB_PK_PARAM_PATH"
      value = "/github/${var.github_user}"
    }

    environment_variable {
      name  = "TARGET_ENVIRONMENT"
      value = var.target_env
    }

    environment_variable {
      name  = "TERRAFORM_STATE_BUCKET"
      value = var.remote_state.bucket_name
    }

    environment_variable {
      name  = "TERRAFORM_STATE_KMS_KEY_ARN"
      value = var.remote_state.key_arn
    }

    environment_variable {
      name  = "TERRAFORM_STATE_LOCKING_TABLE"
      value = var.remote_state.locking_table_name
    }

    environment_variable {
      name  = "TERRAFORM_STATE_REGION"
      value = var.remote_state_region
    }
  }

  service_role  = aws_iam_role.tools_deployer.arn
  build_timeout = var.build_timeout
}
