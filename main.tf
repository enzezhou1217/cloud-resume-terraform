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
      name = "cloud-resume"
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
resource "aws_lambda_permission" "lambda_permission" {
  statement_id  = "AllowAPIToInvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = "cloud-resume-lambda"
  principal     = "apigateway.amazonaws.com"

  # The /*/*/* part allows invocation from any stage, method and resource path
  # within API Gateway REST API.
  source_arn = "${aws_apigatewayv2_api.api-to-invoke-lambda.execution_arn}/*/*/*"
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
#lambda roles
resource "aws_iam_role_policy_attachment" "lambda_policy" {
   role = aws_iam_role.iam_for_lambda.name
   policy_arn = "arn:aws:iam::aws:policy/servicerole/AWSLambdaBasicExecutionRole"
}         
resource "aws_iam_role_policy" "dynamodb-lambda-policy" {
   name = "dynamodb_lambda_policy"
   role = aws_iam_role.iam_for_lambda.id
   policy = jsonencode({
      "Version" : "2012-10-17",
      "Statement" : [
        {
           "Effect" : "Allow",
           "Action" : ["dynamodb:*"],
           "Resource" : "${aws_dynamodb_table.cloud-resume-table.arn}"
        }
      ]
   })
}

resource "aws_lambda_function" "cloud-resume-lambda" {
  filename         = "cloud-resume-lambda.zip"
  function_name    = "cloud-resume-lambda"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.8"
}

#api lambda integration
resource "aws_apigatewayv2_integration" "lambda-api-integration" {
  api_id           = aws_apigatewayv2_api.api-to-invoke-lambda.id
  integration_type = "AWS_PROXY"

  connection_type           = "INTERNET"
  #content_handling_strategy = "CONVERT_TO_TEXT"
  description               = "lambda-api-integration"
  integration_method        = "POST"
  integration_uri           = aws_lambda_function.cloud-resume-lambda.invoke_arn
  passthrough_behavior      = "WHEN_NO_MATCH"
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
  # Add specefic S3 policy in the s3-policy.json on the same directory
  #policy = file("s3-policy.json")
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

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.mybucket.bucket_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
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
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE", "IN", "IR"]
    }
  }

  tags = {
    Name = "cloud-resume-cloudfront"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

#add route53 records
resource "aws_route53_record" "ipv4" {
  zone_id = aws_route53_zone.cloud-resume-hosted-zone.zone_id
  name    = "enzezhou.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
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