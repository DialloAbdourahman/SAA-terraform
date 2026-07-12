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

resource "aws_subnet" "subnet_az_1b_second" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-north-1b"

  map_public_ip_on_launch = true

  tags = {
    Name = "Subnet AZ 1b second"
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

resource "aws_route_table_association" "sub2_rta_second" {
  subnet_id      = aws_subnet.subnet_az_1b_second.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  vpc_id      = aws_vpc.myvpc.id

  tags = {
    Name = "ec2_sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "efs_sg" {
  name        = "efs_sg"
  vpc_id      = aws_vpc.myvpc.id

  tags = {
    Name = "efs_sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_efs_ipv4" {
  security_group_id            = aws_security_group.efs_sg.id
  referenced_security_group_id = aws_security_group.ec2_sg.id
  from_port                    = 2049
  ip_protocol                  = "tcp"
  to_port                      = 2049
}

resource "aws_efs_file_system" "efs" {
  creation_token = "chopme-efs"
}

resource "aws_efs_mount_target" "subnet_a" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = aws_subnet.subnet_az_1a.id
  security_groups = [aws_security_group.efs_sg.id]

  depends_on = [aws_efs_file_system.efs]
}

resource "aws_efs_mount_target" "subnet_b" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = aws_subnet.subnet_az_1b.id
  security_groups = [aws_security_group.efs_sg.id]

  depends_on = [aws_efs_file_system.efs]
}

resource "aws_instance" "web_server_az_a" {
  ami           = "ami-0974a2c5ddf10f442"
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id = aws_subnet.subnet_az_1a.id
  associate_public_ip_address = true

  user_data = templatefile("user-data.sh", {
    efs_ip = aws_efs_mount_target.subnet_a.ip_address
  })

  user_data_replace_on_change = true

  tags = {
    Name = "web_server_az_a"
  }

  depends_on = [aws_efs_mount_target.subnet_a]
}

resource "aws_instance" "web_server_az_b" {
  ami           = "ami-0974a2c5ddf10f442"
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id = aws_subnet.subnet_az_1b.id
  associate_public_ip_address = true

  user_data = templatefile("user-data.sh", {
    efs_ip = aws_efs_mount_target.subnet_b.ip_address
  })

  user_data_replace_on_change = true

  tags = {
    Name = "web_server_az_b"
  }

  depends_on = [aws_efs_mount_target.subnet_b]

}

// Just to show that we can have multiple instances in different subnets but same availability zone
resource "aws_instance" "web_server_az_b_second" {
  ami           = "ami-0974a2c5ddf10f442"
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id = aws_subnet.subnet_az_1b_second.id
  associate_public_ip_address = true

  user_data = templatefile("user-data.sh", {
    efs_ip = aws_efs_mount_target.subnet_b.ip_address
  })

  user_data_replace_on_change = true

  tags = {
    Name = "web_server_az_b_second"
  }

  depends_on = [aws_efs_mount_target.subnet_b]

}

