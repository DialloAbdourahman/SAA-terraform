provider "aws" {
  region = "eu-north-1"
}

resource "aws_vpc" "myvpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "myvpc"
  }
}

resource "aws_subnet" "subnet_az_1a" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "eu-north-1a"

  map_public_ip_on_launch = true

  tags = {
    Name = "Subnet AZ 1a"
  }
}

resource "aws_subnet" "subnet_az_1b" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-north-1b"

  map_public_ip_on_launch = true

  tags = {
    Name = "Subnet AZ 1b"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "Internet gateway"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Public route table"
  }
}

resource "aws_route_table_association" "sub1_rta" {
  subnet_id      = aws_subnet.subnet_az_1a.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "sub2_rta" {
  subnet_id      = aws_subnet.subnet_az_1b.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "alb_sg" {
  name        = "alb_sg"
  vpc_id      = aws_vpc.myvpc.id

  tags = {
    Name = "alb_sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_for_alb" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "allow_alb_outbound" {
  security_group_id = aws_security_group.alb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  vpc_id      = aws_vpc.myvpc.id

  tags = {
    Name = "ec2_sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_from_alb" {
  security_group_id = aws_security_group.ec2_sg.id
  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

# resource "aws_vpc_security_group_ingress_rule" "allow_http_temporal_for_tests" {
#   security_group_id = aws_security_group.ec2_sg.id
#   cidr_ipv4         = "0.0.0.0/0"
#   from_port         = 80
#   ip_protocol       = "tcp"
#   to_port           = 80
# }

resource "aws_vpc_security_group_egress_rule" "allow_all_ec2_outbound" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_lb_target_group" "auth_service_tg" {
  name     = "auth-service-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.myvpc.id

  # stickiness {
  #   type            = "lb_cookie"
  #   cookie_duration = 86400  # Time in seconds (1 day)
  #   enabled         = true
  # }

  health_check {
    path = "/"
    port = "traffic-port"
  }
}

resource "aws_launch_template" "auth_service_lt" {
  name_prefix   = "auth-service-lt"
  image_id      = "ami-0974a2c5ddf10f442"
  instance_type = "t3.micro"

  # Network interfaces
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  # User data (bootstrap script)
  user_data = base64encode(file("userdata.sh"))

  # Tags for instances launched from this template
  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "auth-service-instance"
    }
  }
}

resource "aws_autoscaling_group" "auth_service_asg" {
  name                 = "auth-service-asg"
  max_size             = 4
  min_size             = 1
  desired_capacity     = 1

  launch_template {
    id      = aws_launch_template.auth_service_lt.id
    version = "$Latest"  
  }

  vpc_zone_identifier = [aws_subnet.subnet_az_1a.id, aws_subnet.subnet_az_1b.id]

  target_group_arns = [aws_lb_target_group.auth_service_tg.arn]

  tag {
    key                 = "Name"
    value               = "auth-service-instance"
    propagate_at_launch = true
  }

  health_check_type         = "EC2"  
  health_check_grace_period = 10    

  force_delete = true  
}

resource "aws_autoscaling_policy" "auth_service_target_tracking" {
  name                   = "auth-service-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.auth_service_asg.name

  policy_type = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {

      # Average CPU utilization across all EC2 instances
      predefined_metric_type = "ASGAverageCPUUtilization"

      # Average incoming network traffic (bytes/sec)
      # predefined_metric_type = "ASGAverageNetworkIn"

      # Average outgoing network traffic (bytes/sec)
      # predefined_metric_type = "ASGAverageNetworkOut"

      # Average requests per healthy target behind an ALB
      # Requires: resource_label = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.auth_service_tg.arn_suffix}"
      # predefined_metric_type = "ALBRequestCountPerTarget"
    }

    target_value     = 50.0
    disable_scale_in = false
  }
}

resource "aws_lb" "myalb" {
  name               = "myalb"
  internal           = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb_sg.id]
  subnets         = [aws_subnet.subnet_az_1a.id, aws_subnet.subnet_az_1b.id]

  tags = {
    Name = "myalb"
  }
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.myalb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    
    fixed_response {
      content_type = "text/plain"
      message_body = "Default route - no specific service configured"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "auth_service_rule" {
  listener_arn = aws_lb_listener.alb_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auth_service_tg.arn
  }

  condition {
    path_pattern {
      values = ["/api/auth*"]
    }
  }
}
