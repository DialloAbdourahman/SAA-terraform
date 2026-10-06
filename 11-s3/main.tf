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

# Rule metadata (id and status)
# Filter identifying objects to which the rule applies
# One or more transition or expiration actions
# We can filter based on tags, objects size, prefix, size range, 
resource "aws_s3_bucket_lifecycle_configuration" "example-rule" {
  bucket = aws_s3_bucket.bucket.bucket

  rule {
    id = "current-version-rule"

    filter {
        # If no prefix/filter, it will apply to all objects 
        #   prefix = "logs/"
    }

    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 60
      storage_class = "GLACIER_IR"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    expiration {
      days = 730
    }
  }

  rule {
    id = "noncurrent-version-rule"

    filter {}

    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days          = 30
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days          = 60
      storage_class = "GLACIER_IR"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  # S3 removes an expired delete marker when it qualifies—specifically, when it is the only remaining version of that object.
  rule {
    id = "delete-marker-cleanup"

    filter {}

    status = "Enabled"

    expiration {
        expired_object_delete_marker = true
    }
  }
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


// ENCRYPTION STUFF

# resource "aws_kms_key" "s3" {
#   description             = "KMS key for S3 bucket encryption"
#   deletion_window_in_days = 30
# }

# resource "aws_kms_alias" "s3" {
#   name          = "alias/chopme-s3"
#   target_key_id = aws_kms_key.s3.key_id
# }

# resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
#   bucket = aws_s3_bucket.this.id

#   rule {
#     apply_server_side_encryption_by_default {
#       sse_algorithm     = "aws:kms"
#       kms_master_key_id = aws_kms_key.s3.arn
#     }
#   }
# }