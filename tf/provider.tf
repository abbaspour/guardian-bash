terraform {
  required_version = "~> 1.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 6.28"
    }
    auth0 = {
      source = "auth0/auth0"
      version = "~> 1.38"
    }
  }
}

provider "aws" {
  region = var.aws_region
  profile = var.aws_profile
}

provider "auth0" {
  domain = var.auth0_domain
  client_id = var.auth0_tf_client_id
  client_secret = var.auth0_tf_client_secret
}
