provider "aws" {
  region = "eu-north-1"
}

variable "worker_count" {
  type    = number
  default = 3
}

resource "aws_security_group" "http_ssh_sg" {
  name        = "http_ssh_sg"
  description = "Allow HTTP and SSH inbound traffic and all outbound traffic"

  tags = {
    Name = "http_ssh_sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.http_ssh_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.http_ssh_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.http_ssh_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" 
}

resource "aws_iam_role" "spot_fleet_role" {
  name = "my-spot-fleet-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "spotfleet.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "spot_fleet_policy_attach" {
  role       = aws_iam_role.spot_fleet_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}

resource "aws_launch_template" "spot_fleet_launch_template" {
  name          = "spot-fleet-launch-template"
  image_id      = "ami-0974a2c5ddf10f442"
  instance_type = "t3.micro"
  key_name      = "ec2-key-pair"
  vpc_security_group_ids = [aws_security_group.http_ssh_sg.id]

  tags = {
    Name = "SpotInstanceWorker"
  }
}

resource "aws_spot_fleet_request" "spot_fleet_request" {
  iam_fleet_role  = aws_iam_role.spot_fleet_role.arn
  spot_price      = "1"
  target_capacity = var.worker_count
  valid_until     = "2026-06-24T11:00:00Z"

  # Maintains target capacity over time (makes the fleet persistent)
  fleet_type = "maintain"
  instance_interruption_behaviour = "stop"

  launch_template_config {
    launch_template_specification {
      id      = aws_launch_template.spot_fleet_launch_template.id
      version = aws_launch_template.spot_fleet_launch_template.latest_version
    }
  }

  depends_on = [aws_iam_role_policy_attachment.spot_fleet_policy_attach]

  tags = {
    Name = "SpotFleetRequest"
  }
}