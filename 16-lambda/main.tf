provider "aws" {
  region = "eu-west-3"
}

resource "aws_s3_bucket" "bucket" {
  bucket = "my-bucket-diallo-testing"

  force_destroy = true
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id

  # Send S3 events to EventBridge
  eventbridge = true

  # Send ObjectCreated:Put directly to SQS
  queue {
    queue_arn = aws_sqs_queue.terraform_queue.arn

    events = [
      "s3:ObjectCreated:Put"
    ]
  }

  depends_on = [
    aws_sqs_queue_policy.terraform_queue_policy
  ]
}

resource "aws_sqs_queue" "terraform_queue" {
  name = "terraform-example-queue"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.terraform_queue_deadletter.arn
    maxReceiveCount     = 4
  })
}

resource "aws_sqs_queue" "terraform_queue_deadletter" {
  name = "terraform-example-deadletter-queue"
}

resource "aws_sqs_queue_redrive_allow_policy" "terraform_queue_redrive_allow_policy" {
  queue_url = aws_sqs_queue.terraform_queue_deadletter.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.terraform_queue.arn]
  })
}

resource "aws_sqs_queue_policy" "terraform_queue_policy" {
  queue_url = aws_sqs_queue.terraform_queue.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowS3SendMessage"
        Effect = "Allow"

        Principal = {
          Service = "s3.amazonaws.com"
        }

        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.terraform_queue.arn

        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.bucket.arn
          }
        }
      }
    ]
  })
}

resource "aws_lambda_event_source_mapping" "s3_to_lambda" {
  event_source_arn = aws_sqs_queue.terraform_queue.arn
  function_name    = aws_lambda_function.s3_image_converter.arn
  batch_size       = 10

  scaling_config {
    maximum_concurrency = 100
  }

  depends_on = [
    aws_sqs_queue_policy.terraform_queue_policy,
    aws_s3_bucket_notification.bucket_notification,
    aws_lambda_function.s3_image_converter
  ]
}


resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "lambda.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_sqs_policy" {
  name = "lambda-sqs-consumer-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]

        Resource = aws_sqs_queue.terraform_queue.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda-s3-access-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]

        Resource = "${aws_s3_bucket.bucket.arn}/*"
      },
      {
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = aws_s3_bucket.bucket.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role = aws_iam_role.lambda_execution_role.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-function"
  output_path = "${path.module}/lambda.zip"
}

# Lambda function
resource "aws_lambda_function" "s3_image_converter" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "s3_image_converter_lambda_function"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "index.handler"

  runtime = "nodejs24.x"

  environment {
    variables = {
      ENVIRONMENT    = "production"
      LOG_LEVEL      = "info"
      TARGET_WIDTH   = "300"
      TARGET_HEIGHT  = "300"
      OUTPUT_PREFIX  = "resized/"
      QUEUE_URL      = aws_sqs_queue.terraform_queue.url
    }
  }

  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
    log_group  = aws_cloudwatch_log_group.lambda_log_group.name
  }

  tags = {
    Environment = "production"
    Application = "example"
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_log_group
  ]
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/s3_image_converter_lambda_function"
  retention_in_days = 14

  tags = {
    Environment = "production"
    Application = "s3_image_converter"
  }
}