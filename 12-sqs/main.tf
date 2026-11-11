provider "aws" {
  region = "eu-west-3"
}

resource "aws_sqs_queue" "terraform_standard_sqs_queue" {
  name = "terraform-standard-queue"

  sqs_managed_sse_enabled = true
  visibility_timeout_seconds = 60
  receive_wait_time_seconds = 20

#   redrive_policy = jsonencode({
#     deadLetterTargetArn = aws_sqs_queue.terraform_queue_deadletter.arn
#     maxReceiveCount     = 4
#   })
}

resource "aws_sqs_queue" "terraform_fifo_sqs_queue" {
  name = "terraform-fifo-queue.fifo"

  sqs_managed_sse_enabled = true
  visibility_timeout_seconds = 60
  receive_wait_time_seconds = 20
  fifo_queue = true
}


# resource "aws_cloudwatch_metric_alarm" "sqs_queue_high" {
#   alarm_name          = "sqs-queue-high"
#   comparison_operator = "GreaterThanThreshold"

#   evaluation_periods  = 1
#   metric_name         = "ApproximateNumberOfMessagesVisible"
#   namespace           = "AWS/SQS"

#   period              = 60
#   statistic           = "Average"

#   threshold           = 100

#   dimensions = {
#     QueueName = aws_sqs_queue.worker_queue.name
#   }

#   alarm_description = "SQS queue backlog is too high"
#   alarm_actions     = [
#     aws_autoscaling_policy.scale_out.arn
#   ]
# }

# resource "aws_autoscaling_policy" "scale_out" {
#   name                   = "sqs-scale-out"
#   autoscaling_group_name = aws_autoscaling_group.auth_service_asg.name

#   adjustment_type = "ChangeInCapacity"
#   policy_type     = "StepScaling"

#   metric_aggregation_type = "Average"
#   cooldown                = 60

#   step_adjustment {
#     metric_interval_lower_bound = 0
#     scaling_adjustment          = 1
#   }
# }