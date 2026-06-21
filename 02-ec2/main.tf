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
  security_groups = [aws_security_group.http_ssh_sg.name]

  user_data_base64 = base64encode(file("userdata/user-data.sh"))
}
