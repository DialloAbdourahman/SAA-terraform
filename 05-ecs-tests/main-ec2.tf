# ============================================================
# ECS EC2 Launch Type Example
# Existing resources expected:
# - aws_vpc.main
# - aws_subnet.public_a
# - aws_subnet.public_b
# - aws_subnet.private_a
# - aws_subnet.private_b
# - aws_ecr_repository.auth
# - aws_ecr_repository.notification
# - aws_iam_role.ecs_execution
# ============================================================


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


# ============================================================
# ECS CLUSTER
# ============================================================

resource "aws_ecs_cluster" "main" {
  name = "production-cluster"
}



# ============================================================
# SECURITY GROUPS
# ============================================================


# ALB Security Group

resource "aws_security_group" "alb" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



# EC2 ECS Container Instance Security Group

resource "aws_security_group" "ecs_instance" {
  name   = "ecs-instance-sg"
  vpc_id = aws_vpc.main.id

  # Allow traffic from ALB to containers
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"

    security_groups = [
      aws_security_group.alb.id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



# ============================================================
# IAM ROLE FOR ECS EC2 INSTANCES
# ============================================================


resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs-instance-role"

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

resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# ============================================================
# ECS EC2 LAUNCH TEMPLATE
# ============================================================

resource "aws_launch_template" "ecs" {
  name = "ecs-container-instance"

  # ECS Optimized Amazon Linux AMI
  image_id = "ami-0c7217cdde317cfec"

  instance_type = "t3.medium"

  iam_instance_profile {

    name = aws_iam_instance_profile.ecs_instance.name
  }

  vpc_security_group_ids = [
    aws_security_group.ecs_instance.id
  ]


  # This is where we say that this ec2 instance belongs to this cluster. 
  user_data = base64encode(<<EOF
    #!/bin/bash

    echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config

    EOF
  )

  tag_specifications {

    resource_type = "instance"


    tags = {

      Name = "ecs-container-instance"
    }
  }
}



# ============================================================
# AUTO SCALING GROUP FOR ECS INSTANCES
# ============================================================


resource "aws_autoscaling_group" "ecs" {
  name             = "ecs-asg"
  desired_capacity = 2
  min_size         = 1
  max_size         = 5

  vpc_zone_identifier = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

}

# ============================================================
# APPLICATION LOAD BALANCER
# ============================================================


resource "aws_lb" "main" {
  name               = "production-alb"
  load_balancer_type = "application"
  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]


  security_groups = [
    aws_security_group.alb.id
  ]

}



# ============================================================
# TARGET GROUPS
# ============================================================


resource "aws_lb_target_group" "auth" {
  name     = "auth-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # ECS EC2 with awsvpc registers task IPs
  target_type = "ip"

  health_check {

    path = "/health"

  }
}



resource "aws_lb_target_group" "notification" {
  name        = "notification-tg"
  port        = 3001
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {

    path = "/health"

  }
}



# ============================================================
# ALB LISTENER
# ============================================================


resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"

    }

  }
}



resource "aws_lb_listener_rule" "auth" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  condition {
    path_pattern {
      values = [
        "/auth/*"
      ]
    }

  }


  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auth.arn

  }
}



resource "aws_lb_listener_rule" "notification" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  condition {

    path_pattern {

      values = [
        "/notifications/*"
      ]

    }

  }


  action {

    type = "forward"


    target_group_arn = aws_lb_target_group.notification.arn

  }
}



# ============================================================
# TASK DEFINITIONS
# ============================================================


resource "aws_ecs_task_definition" "auth" {


  family = "auth-service"



  requires_compatibilities = [

    "EC2"

  ]



  network_mode = "awsvpc"



  cpu = 512


  memory = 1024



  execution_role_arn = aws_iam_role.ecs_execution.arn



  container_definitions = jsonencode([

    {

      name = "auth"


      image = "${aws_ecr_repository.auth.repository_url}:latest"


      essential = true



      portMappings = [

        {

          containerPort = 3000

        }

      ]

    }

  ])

}




resource "aws_ecs_task_definition" "notification" {


  family = "notification-service"



  requires_compatibilities = [

    "EC2"

  ]



  network_mode = "awsvpc"



  cpu = 256


  memory = 512



  execution_role_arn = aws_iam_role.ecs_execution.arn



  container_definitions = jsonencode([

    {

      name = "notification"


      image = "${aws_ecr_repository.notification.repository_url}:latest"


      essential = true



      portMappings = [

        {

          containerPort = 3001

        }

      ]

    }

  ])

}



# ============================================================
# ECS SERVICES
# ============================================================


resource "aws_ecs_service" "auth" {


  name = "auth-service"



  cluster = aws_ecs_cluster.main.id



  task_definition = aws_ecs_task_definition.auth.arn



  desired_count = 3



  launch_type = "EC2"



  load_balancer {


    target_group_arn = aws_lb_target_group.auth.arn


    container_name = "auth"


    container_port = 3000

  }

}




resource "aws_ecs_service" "notification" {


  name = "notification-service"



  cluster = aws_ecs_cluster.main.id



  task_definition = aws_ecs_task_definition.notification.arn



  desired_count = 2



  launch_type = "EC2"



  load_balancer {


    target_group_arn = aws_lb_target_group.notification.arn


    container_name = "notification"


    container_port = 3001

  }

}