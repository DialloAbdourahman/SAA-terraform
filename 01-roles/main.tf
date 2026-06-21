provider "aws" {
  region = "eu-north-1"
}

// Create S3 bucket
resource "aws_s3_bucket" "data_bucket" {
  bucket = "data-bucket-12du345"
}

// Create IAM role and setting trusted entity
resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

  // Trust policy: Only ec2 service can assume this role using STS
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

// Create IAM policy
resource "aws_iam_policy" "policy" {
  name        = "write_get_s3_bucket_policy"
  path        = "/"
  description = "My test policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.data_bucket.arn}/*"
      }
    ]
  })
}


// Attach policy to role
resource "aws_iam_role_policy_attachment" "ec2_role_policy_attachment" {
  role = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.policy.arn
}