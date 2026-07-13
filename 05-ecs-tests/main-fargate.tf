
# main.tf
# Simplified ECS on Fargate example with ALB
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

# -------------------------------------------------------------------
# Existing infrastructure expected:
# - aws_vpc.main
# - public/private subnets
# - ECR repositories
# - IAM execution role
# -------------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = "production-cluster"
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port=80
    to_port=80
    protocol="tcp"
    cidr_blocks=["0.0.0.0/0"]
  }

  egress {
    from_port=0
    to_port=0
    protocol="-1"
    cidr_blocks=["0.0.0.0/0"]
  }
}

# ECS Tasks Security Group
resource "aws_security_group" "ecs" {
  name   = "ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port=3000
    to_port=3001
    protocol="tcp"
    security_groups=[aws_security_group.alb.id]
  }

  egress {
    from_port=0
    to_port=0
    protocol="-1"
    cidr_blocks=["0.0.0.0/0"]
  }
}

resource "aws_lb" "main" {
  name="production-alb"
  load_balancer_type="application"
  subnets=[
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]
  security_groups=[aws_security_group.alb.id]
}

resource "aws_lb_target_group" "auth" {
  name="auth-tg"
  port=3000
  protocol="HTTP"
  vpc_id=aws_vpc.main.id
  target_type="ip"
  health_check { path="/health" }
}

resource "aws_lb_target_group" "notification" {
  name="notification-tg"
  port=3001
  protocol="HTTP"
  vpc_id=aws_vpc.main.id
  target_type="ip"
  health_check { path="/health" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn=aws_lb.main.arn
  port=80
  protocol="HTTP"

  default_action{
    type="fixed-response"
    fixed_response{
      content_type="text/plain"
      message_body="Not Found"
      status_code="404"
    }
  }
}

resource "aws_lb_listener_rule" "auth" {
  listener_arn=aws_lb_listener.http.arn
  priority=10
  condition {
    path_pattern { values=["/auth/*"] }
  }
  action {
    type="forward"
    target_group_arn=aws_lb_target_group.auth.arn
  }
}

resource "aws_lb_listener_rule" "notification" {
  listener_arn=aws_lb_listener.http.arn
  priority=20
  condition {
    path_pattern { values=["/notifications/*"] }
  }
  action {
    type="forward"
    target_group_arn=aws_lb_target_group.notification.arn
  }
}

resource "aws_ecs_task_definition" "auth" {
  family="auth-service"
  requires_compatibilities=["FARGATE"]
  network_mode="awsvpc"
  cpu=512
  memory=1024
  execution_role_arn=aws_iam_role.ecs_execution.arn

  container_definitions=jsonencode([{
    name="auth"
    image="${aws_ecr_repository.auth.repository_url}:latest"
    essential=true
    portMappings=[{containerPort=3000}]
  }])
}

resource "aws_ecs_task_definition" "notification" {
  family="notification-service"
  requires_compatibilities=["FARGATE"]
  network_mode="awsvpc"
  cpu=256
  memory=512
  execution_role_arn=aws_iam_role.ecs_execution.arn

  container_definitions=jsonencode([{
    name="notification"
    image="${aws_ecr_repository.notification.repository_url}:latest"
    essential=true
    portMappings=[{containerPort=3001}]
  }])
}

resource "aws_ecs_service" "auth" {
  name="auth-service"
  cluster=aws_ecs_cluster.main.id
  task_definition=aws_ecs_task_definition.auth.arn
  desired_count=3
  launch_type="FARGATE"

  network_configuration{
    subnets=[aws_subnet.private_a.id,aws_subnet.private_b.id]
    security_groups=[aws_security_group.ecs.id]
    assign_public_ip=false
  }

  load_balancer{
    target_group_arn=aws_lb_target_group.auth.arn
    container_name="auth"
    container_port=3000
  }
}

resource "aws_ecs_service" "notification" {
  name="notification-service"
  cluster=aws_ecs_cluster.main.id
  task_definition=aws_ecs_task_definition.notification.arn
  desired_count=2
  launch_type="FARGATE"

  network_configuration{
    subnets=[aws_subnet.private_a.id,aws_subnet.private_b.id]
    security_groups=[aws_security_group.ecs.id]
    assign_public_ip=false
  }

  load_balancer{
    target_group_arn=aws_lb_target_group.notification.arn
    container_name="notification"
    container_port=3001
  }
}

# Docker Image (ECR)
#         │
#         ▼
# Task Definition
# (Blueprint describing how to run the container)
#         │
#         ▼
# ECS Service
# (Responsible for running and maintaining tasks)
#         │
#         ▼
# Tasks (Running containers)