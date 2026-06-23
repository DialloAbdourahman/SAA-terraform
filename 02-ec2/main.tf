provider "aws" {
  region = var.aws_region
}

resource "aws_security_group" "http_ssh_sg" {
  name        = "http_ssh_sg"
  description = "Allow HTTP and SSH inbound traffic and all outbound traffic"
#   vpc_id      = aws_vpc.myvpc.id

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

resource "aws_instance" "web_server" {
  ami           = var.ubuntu_ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  vpc_security_group_ids = [aws_security_group.http_ssh_sg.name]

  user_data_base64 = base64encode(file("userdata/user-data.sh"))
}


# The recommended way is not to use security_groups = [...] with security group names. Instead:

# Create both security groups.
# Attach them using vpc_security_group_ids.
# Reference the source security group in the ingress rule.

# Example

# API Gateway Security Group
# resource "aws_security_group" "gateway_sg" {
#   name = "gateway-sg"
# }

# Auth Service Security Group
# resource "aws_security_group" "auth_sg" {
#   name = "auth-sg"
# }

# Allow Gateway to call Auth Service on port 3000
# resource "aws_vpc_security_group_ingress_rule" "allow_gateway_to_auth" {
#   security_group_id            = aws_security_group.auth_sg.id
#   referenced_security_group_id = aws_security_group.gateway_sg.id

#   from_port   = 3000
#   to_port     = 3000
#   ip_protocol = "tcp"
# }

# Notice there is no cidr_ipv4 here.

# Terraform tells AWS:

# "Allow any instance that belongs to gateway_sg."

# Gateway EC2
# resource "aws_instance" "gateway" {
#   ami                    = var.ubuntu_ami_id
#   instance_type          = var.instance_type
#   key_name               = var.key_name
#   vpc_security_group_ids = [aws_security_group.gateway_sg.id]
# }

# Auth EC2
# resource "aws_instance" "auth" {
#   ami                    = var.ubuntu_ami_id
#   instance_type          = var.instance_type
#   key_name               = var.key_name
#   vpc_security_group_ids = [aws_security_group.auth_sg.id]
# }

# For RabbitMQ

# Suppose RabbitMQ has its own security group.

# resource "aws_security_group" "rabbitmq_sg" {
#   name = "rabbitmq-sg"
# }

# Allow the Auth service to connect:

# resource "aws_vpc_security_group_ingress_rule" "auth_to_rabbitmq" {
#   security_group_id            = aws_security_group.rabbitmq_sg.id
#   referenced_security_group_id = aws_security_group.auth_sg.id

#   from_port   = 5672
#   to_port     = 5672
#   ip_protocol = "tcp"
# }

# If the Notification service also needs RabbitMQ, add another rule:

# resource "aws_vpc_security_group_ingress_rule" "notification_to_rabbitmq" {
#   security_group_id            = aws_security_group.rabbitmq_sg.id
#   referenced_security_group_id = aws_security_group.notification_sg.id

#   from_port   = 5672
#   to_port     = 5672
#   ip_protocol = "tcp"
# }
# One improvement to your current code

# Instead of:

# security_groups = [aws_security_group.http_ssh_sg.name]

# prefer:

# vpc_security_group_ids = [aws_security_group.http_ssh_sg.id]

# Using vpc_security_group_ids is the modern and recommended approach for EC2 instances in a VPC. It avoids issues with name resolution and makes dependencies explicit.

# For a microservices architecture (Gateway, Auth, Notifications, Stats, RabbitMQ), I recommend giving each service its own security group and allowing communication by referencing security groups rather than opening ports to IP ranges. This is more secure and scales much better as you add services.