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

# # Configure the Okta Provider
# provider "okta" {}

# resource "okta_app_oauth" "brittany" {
#   label          = "brittany"
#   type           = "browser"
#   grant_types    = ["authorization_code", "implicit"]
#   redirect_uris  = ["https://example.com/"]
#   response_types = ["token", "id_token", "code"]
# }




resource "aws_appsync_graphql_api" "okta-example-api" {
  name                = "okta-example"
  authentication_type = "OPENID_CONNECT"


  openid_connect_config {
    issuer = "https://pgpoc.okta.com"
    # client_id = ""
  }

  schema = <<EOF
type Mutation {
    createPost(title: String!, description: String): Post
}

type Post {
    id: ID!
    title: String!
    description: String
    consumerId: ID
}

type Query {
    listPosts: [Post]
}

schema {
    query: Query
    mutation: Mutation
}
EOF
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
  name = "example"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "appsync.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "okta-example-policy" {
  name = "example"
  role = aws_iam_role.okta-example-role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "dynamodb:*"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_dynamodb_table.okta-example-table.arn}"
      ]
    }
  ]
}
EOF
}