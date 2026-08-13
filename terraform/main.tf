terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Generates the in-stack API signing key -- see ssm.tf.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket         = "xomware-terraform-state"
    key            = "today-in-sports/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "xomware-terraform-locks"
    encrypt        = true
  }
}

data "aws_caller_identity" "web_app_account" {
  provider = aws
}
