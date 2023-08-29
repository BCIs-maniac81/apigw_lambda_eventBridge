data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Create an API Gateway HTTP with integration via EventBridge
resource "aws_apigatewayv2_api" "api_gateway_http_api" {
  name          = "apigw-http-api-eb"
  protocol_type = "HTTP"
  body = jsonencode({
    "openapi" : "3.0.1",
    "info" : {
      "title" : "API Gateway HTTP API to EventBridge"
    },
    "paths" : {
      "/" : {
        "POST" : {
          "responses" : {
            "default" : {
              "description" : "EventBridge response"
            }
          },
          "x-amazon-apigateway-integration" : {
            "integrationSubtype" : "EventBridge-PutEvents",
            "credentials" : "${aws_iam_role.APIGWRole.arn}",
            "RequestParameters" : {
              "Detail" : "$request.body.Detail",
              "DetailType" : "MyDetailType",
              "Source" : "demo.apigw"
            },
            "payloadFormatVersion" : "1.0",
            "type" : "aws_proxy"
            "connectiontype" : "INTERNET"
          }
        }
      }
    }

  })
}

# Create an API Gateway Stage with Automatic deployment

resource "aws_apigatewayv2_stage" "api_gateway_http_api_stage" {
  api_id      = aws_apigatewayv2_api.api_gateway_http_api.id
  name        = "$default"
  auto_deploy = true
}

# create IAM Role for API Gateway

resource "aws_iam_role" "APIGWRole" {
  assume_role_policy = <<POLICY1
    {
        "Version" : "2012-10-17",
        "Statement" : [
            {
                "Effect" : "Allow",
                "Principal" : {
                "Service" : "apigateway.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
            }
        ]
    }
    POLICY1
}

# Create an IAM policy for API Gateway to write to create an eventBridge event

resource "aws_iam_policy" "APIGWPolicy" {
  policy = <<POLICY2
  {
        "Version" : "2012-10-17",
        "Statement" : [
          {
            "Effect" : "Allow",
            "Action": [
                "events:PutEvents"
            ],
            "Resource": ["arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:event-bus/default"]
          }
        ]
    }
    POLICY2
}

# Attach the IAM policies to the equivalent role

resource "aws_iam_role_policy_attachment" "APIGWPolicyAttchment" {
  role       = aws_iam_role.APIGWRole.name
  policy_arn = aws_iam_policy.APIGWPolicy.arn
}


# Create a new Event Rule

resource "aws_cloudwatch_event_rule" "MyEventRule" {
  event_pattern = <<PATTERN
    {
        "account": ["${data.aws_caller_identity.current.account_id}"],
        "source" : ["demo.apigw"]
    }
    PATTERN
}

# Set the lambda function as a CloudWatch event target

resource "aws_cloudwatch_event_target" "MyRuleTarget" {
  arn  = aws_lambda_function.MyLambdaFunction.arn
  rule = aws_cloudwatch_event_rule.MyEventRule.id
}

# Create a zip file from lambda source code

data "archive_file" "LambdaZipFile" {
  type        = "zip"
  source_file = "${path.module}/src/lambda-function.py"
  output_path = "${path.module}/lambda-function.zip"
}

# Create Lambda function

resource "aws_lambda_function" "MyLambdaFunction" {
  function_name    = "apigw-http-eventbridge-terraform-demo-${data.aws_caller_identity.current.account_id}"
  filename         = data.archive_file.LambdaZipFile.output_path
  source_code_hash = filebase64sha256(data.archive_file.LambdaZipFile.output_path)
  role             = aws_iam_role.LambdaRole.arn
  handler          = "lambda-function.lambda_handler"
  runtime          = "python3.11"
  layers           = ["arn:aws:lambda:${data.aws_region.current.name}:017000801446:layer:AWSLambdaPowerToolsPython:15"]
}

# Allow the event bridge rule created to invoke the lambda function
resource "aws_lambda_permission" "EventBridgeLambdaPermission" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.MyLambdaFunction.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.MyEventRule.arn
}

# Create IAM role for lambda

resource "aws_iam_role" "LambdaRole" {
  assume_role_policy = <<POLICY3
    {
        "Version" : "2012-10-17",
        "Statement" : [
            {
                "Effect" : "Allow",
                "Principal" : {
                    "Service" : "lambda.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }
    POLICY3
}

# Create an IAM policy for Lambda to push CloudWatch logs

resource "aws_iam_policy" "LambdaPolicy" {
  policy = <<POLICY4
    {
        "indented":"true",
        "Version" : "2012-10-17",
        "Statement" : [
            {
                "Effect" : "Allow",
                "Action": [
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                    ],
                    "Resource" : "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda${aws_lambda_function.MyLambdaFunction.function_name}:*:*"
        ]
    }
    POLICY4
}

# Attach 

resource "aws_iam_role_policy_attachment" "LambdaPolicyAttachement" {
  role       = aws_iam_role.LambdaRole.name
  policy_arn = aws_iam_policy.LambdaPolicy
}

# Create a log group for the lambda function with 60 days retention period

resource "aws_cloudwatch_log_group" "MyLogGroup" {
  name              = "/aws/lambda/${aws_lambda_function.MyLambdaFunction.function_name}"
  retention_in_days = 60
}

output "APIGW-URL" {
  value       = aws_apigatewayv2_stage.api_gateway_http_api_stage.invoke_url
  description = "The API Gateway Invokation URL Queue URL"
}

output "LambdaFunctionName" {
  value       = aws_lambda_function.MyLambdaFunction.function_name
  description = "The Lambda function Name"
}

output "CloudWatchLogName" {
  value       = "/aws/lambda/${aws_lambda_function.MyLambdaFunction.function_name}"
  description = "The Lambda function Log Group"
}