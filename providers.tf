terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region              = "eu-central-1"
  shared_config_files = ["~/.aws/credentials"]
}