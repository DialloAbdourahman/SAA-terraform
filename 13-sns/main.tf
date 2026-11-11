provider "aws" {
  region = "eu-west-3"
}

resource "aws_sns_topic" "user_updates" {
  name = "user-updates-topic"

  tags = {
    Name = "user-updates-topic"
  }
}

resource "aws_sqs_queue" "user_analytics_queue" {
  name = "user-analytics-queue"

  tags = {
    Name = "user-analytics-queue"
  }
}

resource "aws_sqs_queue_policy" "user_analytics_queue_policy" {
  queue_url = aws_sqs_queue.user_analytics_queue.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowSNSSendMessage"
        Effect = "Allow"

        Principal = {
          Service = "sns.amazonaws.com"
        }

        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.user_analytics_queue.arn

        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.user_updates.arn
          }
        }
      }
    ]
  })
}

resource "aws_sqs_queue" "user_notifications_queue" {
  name = "user-notifications-queue"

  tags = {
    Name = "user-notifications-queue"
  }
}

resource "aws_sqs_queue_policy" "user_notifications_queue_policy" {
  queue_url = aws_sqs_queue.user_notifications_queue.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowSNSSendMessage"
        Effect = "Allow"

        Principal = {
          Service = "sns.amazonaws.com"
        }

        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.user_notifications_queue.arn

        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.user_updates.arn
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "user_analytics_sqs_target" {
  topic_arn = "${aws_sns_topic.user_updates.arn}"
  protocol  = "sqs"
  endpoint  = "${aws_sqs_queue.user_analytics_queue.arn}"
}

resource "aws_sns_topic_subscription" "user_notifications_sqs_target" {
  topic_arn = "${aws_sns_topic.user_updates.arn}"
  protocol  = "sqs"
  endpoint  = "${aws_sqs_queue.user_notifications_queue.arn}"
}

# interface ParsedMessage<T = unknown> {
#   source: 'SQS' | 'SNS';
#   data: T;
# }

# function parseMessage<T = unknown>(body: string): ParsedMessage<T> {
#   const parsed = JSON.parse(body);

#   // SNS notification envelope
#   if (
#     parsed.Type === 'Notification' &&
#     typeof parsed.Message === 'string' &&
#     parsed.TopicArn
#   ) {
#     return {
#       source: 'SNS',
#       data: JSON.parse(parsed.Message) as T,
#     };
#   }

#   // Direct SQS message or SNS raw delivery
#   return {
#     source: 'SQS',
#     data: parsed as T,
#   };
# }