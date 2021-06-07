terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
    okta = {
      source = "okta/okta"
      version = "~> 3.10"
    }
  }

  required_version = ">= 0.13.4"
}


# Configure the AWS Provider
provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

# Configure the Okta Provider
provider "okta" {
  org_name  = "dev-123456"
  base_url  = "oktapreview.com"
  api_token = "xxxx"
}

resource "aws_iam_role" "appsync_role" {
  name               = "okta_appsync_terraform_api"
  assume_role_policy = file("${path.module}/templates/appsyncRole.json")
}

resource "aws_iam_role_policy" "appsync_role_policy" {
  name = "okta_appsync_terraform_api_role_policy"
  role = aws_iam_role.appsync_role.id

  policy = templatefile("${path.module}/templates/appsyncPolicy.json", {
    region     = "us-east-1",
  })
}

resource "aws_appsync_graphql_api" "example" {
  authentication_type = "OPENID_CONNECT"
  name                = "okta_appsync_terraform"

  schema = file("${path.module}/templates/okta_appsync_terraform.graphql")

  openid_connect_config {
    issuer = "https://example.com"
    # client_id = ""
  }
}
