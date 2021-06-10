terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
    okta = {
      source  = "okta/okta"
      version = "~> 3.10"
    }
  }

  required_version = ">= 0.13.4"
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

# Configure the Okta Provider
provider "okta" {}

resource "okta_app_oauth" "openID-connect" {
  label          = "openID-connect"
  type           = "browser"
  grant_types    = ["authorization_code", "implicit"]
  redirect_uris  = ["http://localhost:8080/login/callback", "https://aws.amazon.com"]
  login_uri      = "http://localhost:8080"
  response_types = ["token", "id_token", "code"]
  # need token_endpoint_auth_method to be set to none for enabling PKCE flow
  token_endpoint_auth_method = "none"
}

# this group creation is used for self service registration and adds members who register here
resource "okta_group" "openID-connect" {
  name        = "openID-connect-group"
  description = "This is an example group for users who create an account to be added to which in turn has access to oktc example app"
}

#assign group okta_app_oauth so users who creat accounts and are in that group have access to the app
resource "okta_app_group_assignment" "openID-connect" {
  app_id   = okta_app_oauth.openID-connect.id
  group_id = okta_group.openID-connect.id
}

# create one for each uri that you want the app to be able to trust for sign in/registration
resource "okta_trusted_origin" "localhost" {
  name   = "http://localhost:8080"
  origin = "http://localhost:8080"
  scopes = ["CORS"]
}

# TODO: see if there's a way to self-service-registration assign to group to add more apps. 

resource "aws_appsync_graphql_api" "okta-example-api" {
  name                = "okta-example"
  authentication_type = "OPENID_CONNECT"


  openid_connect_config {
    issuer = "https://pgpoc.okta.com"
    # comment out client_id if you want to open appsync api to all 
    # applications in issuer andnot just a single one
    client_id = okta_app_oauth.openID-connect.client_id
  }

  schema = file("${path.module}/templates/okta_appsync_terraform.graphql")
}

resource "aws_appsync_datasource" "okta-example-datasource" {
  api_id           = aws_appsync_graphql_api.okta-example-api.id
  name             = "tf_appsync_example"
  service_role_arn = aws_iam_role.okta-example-role.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = aws_dynamodb_table.okta-example-table.name
  }
}

resource "aws_appsync_resolver" "createPost_resolver" {
  api_id      = aws_appsync_graphql_api.okta-example-api.id
  field       = "createPost"
  type        = "Mutation"
  data_source = aws_appsync_datasource.okta-example-datasource.name

  request_template = <<EOF
{
    "version": "2018-05-29",
    "operation": "PutItem",
    "key" : {
        "id": $util.dynamodb.toDynamoDBJson($util.autoId()),
        "consumerId": $util.dynamodb.toDynamoDBJson($ctx.identity.sub),
    },
    "attributeValues" : $util.dynamodb.toMapValuesJson($ctx.args)
}
EOF

  response_template = <<EOF
$util.toJson($ctx.result)
EOF
}

resource "aws_appsync_resolver" "listPosts_resolver" {
  api_id      = aws_appsync_graphql_api.okta-example-api.id
  field       = "listPosts"
  type        = "Query"
  data_source = aws_appsync_datasource.okta-example-datasource.name

  request_template = <<EOF
{
    "version": "2018-05-29",
    "operation": "Scan",
    "filter": #if($context.args.filter) $util.transform.toDynamoDBFilterExpression($ctx.args.filter) #else null #end,
    "limit": $util.defaultIfNull($ctx.args.limit, 20),
    "nextToken": $util.toJson($util.defaultIfNullOrEmpty($ctx.args.nextToken, null)),
}
EOF

  response_template = <<EOF
$util.toJson($context.result.items)
EOF
}

resource "aws_dynamodb_table" "okta-example-table" {
  name           = "example"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "id"

    attribute  {
      name = "id"
      type = "S"
    }
}

resource "aws_iam_role" "okta-example-role" {
  name = "okta-example-role"

  assume_role_policy = file("${path.module}/templates/appsyncRole.json")
}

resource "aws_iam_role_policy" "okta-example-policy" {
  name = "octa-example-policy"
  role = aws_iam_role.okta-example-role.id

  policy = templatefile("${path.module}/templates/appsyncPolicy.json", {
    aws_dynamodb_table = "${aws_dynamodb_table.okta-example-table.arn}",
  })
}