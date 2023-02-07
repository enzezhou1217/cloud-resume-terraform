terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  cloud {
    organization = "enzezhou117"

    workspaces {
      name = "cloud-resume-3"
    }
  }

  required_version = ">= 1.2.0"
}


provider "aws" {
  region = "us-east-1"
}

//*******************************************************************************
//API GATEWAY & LAMBDA
#api creation &  permission for api gateway
resource "aws_apigatewayv2_api" "api-to-invoke-lambda" {
  name          = "cloud-resume-http-api-invoke-lambda-terraform"
  protocol_type = "HTTP"
}
resource "aws_apigatewayv2_integration" "http-api-proxy" {
  api_id           = aws_apigatewayv2_api.api-to-invoke-lambda.id
  integration_type = "AWS_PROXY"

  connection_type           = "INTERNET"
  description               = "Lambda integration"
  integration_method        = "POST"
  integration_uri           = aws_lambda_function.cloud-resume-lambda-function.arn
  passthrough_behavior      = "WHEN_NO_MATCH"
}
resource "aws_apigatewayv2_route" "http-api-route" {
  api_id    = aws_apigatewayv2_api.api-to-invoke-lambda.id
  route_key = "$default"

  target = "integrations/${aws_apigatewayv2_integration.http-api-proxy.id}"
}
resource "aws_apigatewayv2_stage" "prod" {
  api_id = aws_apigatewayv2_api.api-to-invoke-lambda.id
  name   = "prod-stage"
  auto_deploy = true
}
#permission to invoke api

resource "aws_lambda_permission" "lambda_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cloud-resume-lambda-function.function_name
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_apigatewayv2_api.api-to-invoke-lambda.execution_arn}/*/*"
}
#iam for lambda & lambda code cip and lambda function creation
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
#policy for dynamo crud
resource "aws_iam_role_policy" "dynamodb-lambda-policy" {
  name = "dynamodb_lambda_policy"
  role = aws_iam_role.iam_for_lambda.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : ["dynamodb:*"],
        "Resource" : aws_dynamodb_table.cloud-resume-table.arn
      }
    ]
  })
}
#function
resource "aws_lambda_function" "cloud-resume-lambda-function" {
  filename         = "cloud-resume-lambda-function.zip"
  function_name    = "cloud-resume-lambda-function"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "cloud-resume-lambda-function.lambda_handler"
  runtime          = "python3.8"
  source_code_hash = filebase64sha256("cloud-resume-lambda-function.zip")
}
resource "aws_lambda_function_url" "for-api-gateway" {
  function_name      = aws_lambda_function.cloud-resume-lambda-function.function_name
  authorization_type = "NONE"
}

//*******************************************************************************
//ACM & DNS validation with Route53
#request certificate for the site
resource "aws_acm_certificate" "cert" {
  domain_name       = "enzezhou.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
#DNS Validation with Route 53
resource "aws_route53_zone" "cloud-resume-hosted-zone" {
  name = "enzezhou.com"
}
resource "aws_route53_record" "cert" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.cloud-resume-hosted-zone.zone_id
}
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert : record.fqdn]
}






//*******************************************************************************
//CloudFront & S3 & Route53 Records
resource "aws_s3_bucket" "mybucket" {
  bucket = "cloud-resume-bucket-enzezhou"
}
resource "aws_s3_bucket_policy" "bucket-policy" {
  bucket = aws_s3_bucket.mybucket.id
  policy = file("s3-policy.json")
}
resource "aws_s3_bucket_website_configuration" "mysite" {
  bucket = aws_s3_bucket.mybucket.bucket

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

locals {
  s3_origin_id = "cloud-resume-bucket-enzezhou"
}
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "cloud-resume-bucket-enzezhou"
}

resource "aws_cloudfront_distribution" "s3_website" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.mysite.website_endpoint
    origin_id   = local.s3_origin_id
    custom_header {
      name = "Referer"
      value = "uXg-Tnd"
    }

    custom_origin_config {
      http_port = "80"
      https_port = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "my-cloudfront"
  default_root_object = "index.html"




  # If you have domain configured use it here
  aliases = ["enzezhou.com"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  tags = {
    Name = "cloud-resume-cloudfront"
  }

  viewer_certificate {
    acm_certificate_arn  = aws_acm_certificate.cert.arn
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

}

#add route53 records
resource "aws_route53_record" "ipv4" {
  zone_id = aws_route53_zone.cloud-resume-hosted-zone.zone_id
  name    = "enzezhou.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_website.domain_name
    zone_id                = aws_cloudfront_distribution.s3_website.hosted_zone_id
    evaluate_target_health = true
  }
}

//*******************************************************************************
//DynamoDB
#dynamodb table and item initialization
resource "aws_dynamodb_table" "cloud-resume-table" {
  name         = "cloud-resume-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "DomainName"
  range_key    = "ID"

  attribute {
    name = "DomainName"
    type = "S"
  }
  attribute {
    name = "ID"
    type = "S"
  }
}

//*******************************************************************************
//CloudWatch alarms & SNS topic & lambda to slack
resource "aws_cloudwatch_metric_alarm" "lambda-error-alarm" {
  alarm_name                = "lambda-error-alarm"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = "1"
  metric_name               = "Errors"
  namespace                 = "AWS/Lambda"
  period                    = "120"
  statistic                 = "Sum"
  threshold                 = "1"
  alarm_description         = "This metric monitors lambda error"
  alarm_actions       = [aws_sns_topic.crc.arn]
  insufficient_data_actions = []
}

resource "aws_cloudwatch_metric_alarm" "lambda-invocation" {
  alarm_name                = "lambda-invocation-alarm"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = "1"
  metric_name               = "Invocations"
  namespace                 = "AWS/Lambda"
  period                    = "60"
  statistic                 = "Sum"
  threshold                 = "10"
  alarm_description         = "This metric monitors lambda invocation spike, 10 visits in 1 minutes"
  alarm_actions       = [aws_sns_topic.crc.arn]
  insufficient_data_actions = []
}

resource "aws_cloudwatch_metric_alarm" "api-latency-alarm" {
  alarm_name                = "api-latency-alarm"
  dimensions                = {
    "ApiName" : "cloud-resume-http-api-invoke-lambda-terraform"
  }
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = "1"
  metric_name               = "Latency"
  namespace                 = "AWS/API_Gateway"
  period                    = "60"
  statistic                 = "Average"
  threshold                 = "1000"
  alarm_description         = "This metric monitors api latency, if average latency > 1s within 1 minute"
  insufficient_data_actions = []
  alarm_actions       = [aws_sns_topic.crc.arn]
}
resource "aws_sns_topic" "crc" {
  name = "crc-metrics-topic"
}
#lambda and slack
resource "aws_lambda_function" "trigger-slack" {
  filename         = "trigger-slack.zip"
  function_name    = "trigger-slack"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "trigger-slack.lambda_handler"
  runtime          = "python3.8"
  source_code_hash = filebase64sha256("trigger-slack.zip")
}
resource "aws_sns_topic_subscription" "user_updates_sqs_target" {
  topic_arn = aws_sns_topic.crc.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.trigger-slack.arn
}
resource "aws_lambda_permission" "lambda_permission_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trigger-slack.function_name
  principal     = "sns.amazonaws.com"
  source_arn = "${aws_sns_topic.crc.arn}"
}
