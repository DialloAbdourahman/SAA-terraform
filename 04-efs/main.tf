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

resource "aws_efs_mount_target" "mount_target_in_subnet_a" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = aws_subnet.subnet_az_1a.id
  security_groups = [aws_security_group.efs_sg.id]

  depends_on = [aws_efs_file_system.efs]
}

resource "aws_efs_mount_target" "mount_target_in_subnet_b" {
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
    efs_ip = aws_efs_mount_target.mount_target_in_subnet_a.ip_address
  })

  user_data_replace_on_change = true

  tags = {
    Name = "web_server_az_a"
  }

  depends_on = [aws_efs_mount_target.mount_target_in_subnet_a]
}

resource "aws_instance" "web_server_az_b" {
  ami           = "ami-0974a2c5ddf10f442"
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id = aws_subnet.subnet_az_1b.id
  associate_public_ip_address = true

  user_data = templatefile("user-data.sh", {
    efs_ip = aws_efs_mount_target.mount_target_in_subnet_b.ip_address
  })

  user_data_replace_on_change = true

  tags = {
    Name = "web_server_az_b"
  }

  depends_on = [aws_efs_mount_target.mount_target_in_subnet_b]

}

resource "aws_instance" "web_server_az_b_second" {
  ami           = "ami-0974a2c5ddf10f442"
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id = aws_subnet.subnet_az_1b_second.id
  associate_public_ip_address = true

  user_data = templatefile("user-data.sh", {
    efs_ip = aws_efs_mount_target.mount_target_in_subnet_b.ip_address
  })

  user_data_replace_on_change = true

  tags = {
    Name = "web_server_az_b_second"
  }

  depends_on = [aws_efs_mount_target.mount_target_in_subnet_b]

}

# ===================================
# EFS & Mount Targets — Quick Summary
# ===================================

# => EFS is a regional service. You create one EFS file system per region, and it can be accessed from any Availability Zone (AZ) in that region.
# => A mount target is a network endpoint (ENI) created inside a specific subnet. It gets a private IP address that EC2 instances use to access the EFS.
# => You can create only one mount target per AZ for a given EFS file system.
# => Each mount target must be placed in a subnet because network interfaces (ENIs) must belong to a subnet.
# => All subnets in the same AZ share that mount target. If you have multiple subnets in an AZ, they all use the same mount target IP.
# => The VPC's automatic local route allows instances in different subnets to communicate, so an EC2 in another subnet of the same AZ can reach the mount target.
# => For best performance and lower cost, create one mount target in every AZ where you run EC2 instances. Then each EC2 mounts EFS through the mount target in its own AZ, avoiding cross-AZ traffic.

# Mental model:

# One EFS (Region)
#        │
#        ├── Mount Target (AZ 1a) → IP 10.0.1.50
#        │       ↑
#        │       └── Used by all EC2s in AZ 1a
#        │
#        └── Mount Target (AZ 1b) → IP 10.0.2.75
#                ↑
#                └── Used by all EC2s in AZ 1b

# => A simple way to remember it is:

# => EFS stores the files, and mount targets provide the IP addresses that EC2 instances use to reach those files.