provider "aws" {
  region = "eu-north-1"
}

resource "aws_vpc" "myvpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "myvpc"
  }
}

resource "aws_subnet" "public_subnet_az_1a" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "eu-north-1a"

  map_public_ip_on_launch = true

  tags = {
    Name = "Public subnet AZ 1a"
  }
}

resource "aws_subnet" "private_subnet_az_1a" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-north-1a"

  map_public_ip_on_launch = false

  tags = {
    Name = "Private subnet AZ 1a"
  }
}

resource "aws_subnet" "public_subnet_az_1b" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-north-1b"

  map_public_ip_on_launch = true

  tags = {
    Name = "Public subnet AZ 1b"
  }
}

resource "aws_subnet" "private_subnet_az_1b" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-north-1b"

  map_public_ip_on_launch = false

  tags = {
    Name = "Private subnet AZ 1b"
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

  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  tags = {
    Name = "Public route table"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  tags = {
    Name = "Private route table"
  }
}

resource "aws_route_table_association" "public_sub1a_rta" {
  subnet_id      = aws_subnet.public_subnet_az_1a.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_sub1a_rta" {
  subnet_id      = aws_subnet.private_subnet_az_1a.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "public_sub2b_rta" {
  subnet_id      = aws_subnet.public_subnet_az_1b.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_sub1b_rta" {
  subnet_id      = aws_subnet.private_subnet_az_1b.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  vpc_id      = aws_vpc.myvpc.id

  tags = {
    Name = "ec2_sg"
  }
}

resource "aws_security_group" "redis_sg" {
  name        = "redis_sg"
  vpc_id      = aws_vpc.myvpc.id

  tags = {
    Name = "redis_sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_allow_http_ipv4" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "ec2_allow_ssh_ipv4" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "ec2_allow_outbound" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "redis_allow_ec2_access" {
  security_group_id = aws_security_group.redis_sg.id
  referenced_security_group_id = aws_security_group.ec2_sg.id
  from_port         = 6379
  ip_protocol       = "tcp"
  to_port           = 6379
}

resource "aws_instance" "ec2_public_subnet_az_1a" {
  ami           = "ami-0974a2c5ddf10f442"
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = aws_subnet.public_subnet_az_1a.id

  user_data_base64 = base64encode(file("userdata.sh"))

  tags = {
    Name = "Public EC2 in AZ1a"
  }
}

resource "aws_instance" "ec2_public_subnet_az_1b" {
  ami           = "ami-0974a2c5ddf10f442"
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id              = aws_subnet.public_subnet_az_1b.id

  user_data_base64 = base64encode(file("userdata.sh"))

  tags = {
    Name = "Public EC2 in AZ1b"
  }
}

resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name = "redis-private-subnet-group"

  subnet_ids = [
    aws_subnet.private_subnet_az_1a.id,
    aws_subnet.private_subnet_az_1b.id
  ]

  tags = {
    Name = "Redis private subnet group"
  }
}

resource "aws_elasticache_cluster" "my_redis_cluster" {
  cluster_id           = "cluster-example"
  engine               = "redis"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis3.2"
  engine_version       = "3.2.10"
  port                 = 6379

  subnet_group_name = aws_elasticache_subnet_group.redis_subnet_group.name

  final_snapshot_identifier = "redis-final-snapshot"

  security_group_ids = [
    aws_security_group.redis_sg.id
  ]

  transit_encryption_enabled = true

  tags = {
    Name = "MyRedisCluster"
  }
}