provider "aws" {
  region = "eu-west-3"
}

resource "aws_kinesis_stream" "test_stream" {
  name             = "terraform-kinesis-test"
  shard_count      = 1
  retention_period = 48

  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Environment = "test"
  }
}

resource "aws_kinesis_firehose_delivery_stream" "extended_s3_stream" {
  name        = "terraform-kinesis-firehose-extended-s3-test-stream"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.test_stream.arn
    role_arn           = aws_iam_role.firehose_role.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.bucket.arn

    # Wait max of 64MB before transfering the data to the bucket (flush).
    buffering_size     = 64 
    # How fast before the buffer is flushed even if the buffering size is not filled. Here for example is 30 seconds.
    buffering_interval = 30

    prefix              = "processed/"
    error_output_prefix = "errors/"
  }
}

resource "aws_s3_bucket" "bucket" {
  bucket = "tf-test-bucket-diallo-2001"
  force_destroy = true
}

resource "aws_iam_role" "firehose_role" {
  name = "firehose_test_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "firehose.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "firehose_s3_policy" {
  name = "firehose_s3_access"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]

        Resource = [
          aws_s3_bucket.bucket.arn,
          "${aws_s3_bucket.bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "firehose_kinesis_policy" {
  name = "firehose_kinesis_access"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListShards"
        ]

        Resource = aws_kinesis_stream.test_stream.arn
      }
    ]
  })
}

# Encryption and compression.

# Messages with the same partition key will go to the same shard

# # PRODUCER

# # CLI v2
# aws kinesis put-record --stream-name terraform-kinesis-test --partition-key the-partition-key --data "user signup" --cli-binary-format raw-in-base64-out

# # CLI v1
# aws kinesis put-record --stream-name terraform-kinesis-test --partition-key the-partition-key --data "user signup"


# # CONSUMER 

# # describe the stream
# aws kinesis describe-stream --stream-name terraform-kinesis-test

# # Consume some data
# aws kinesis get-shard-iterator --stream-name terraform-kinesis-test --shard-id shardId-000000000000 --shard-iterator-type TRIM_HORIZON

# aws kinesis get-records --shard-iterator <>
