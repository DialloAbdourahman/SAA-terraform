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

resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  vpc_id      = aws_vpc.myvpc.id

  tags = {
    Name = "rds_sg"
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

resource "aws_vpc_security_group_ingress_rule" "rds_allow_ec2_access" {
  security_group_id = aws_security_group.rds_sg.id
  referenced_security_group_id = aws_security_group.ec2_sg.id
  from_port         = 3306
  ip_protocol       = "tcp"
  to_port           = 3306
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

resource "aws_db_subnet_group" "db_subnet_group" {
  name = "db-private-subnet-group"

  subnet_ids = [
    aws_subnet.private_subnet_az_1a.id,
    aws_subnet.private_subnet_az_1b.id
  ]

  tags = {
    Name = "DB private subnet group"
  }
}

resource "aws_db_parameter_group" "mysql_secure" {
  name   = "mysql8-secure"
  family = "mysql8.0"

  parameter {
    name  = "require_secure_transport"
    value = "ON"
  }

  tags = {
    Name = "MySQL Secure Parameter Group"
  }
}

resource "aws_rds_cluster" "my_db" {
  cluster_identifier      = "aurora-cluster-demo"
  engine                  = "aurora-mysql"
  engine_version          = "8.0.mysql_aurora.3.10.3"

  #   Can let aurora handle the az in production by looking at the db subnet group. 
  #   availability_zones      = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]

  database_name           = "mydb"
  master_username         = "foo"
  master_password         = "must_be_eight_characters"
  backup_retention_period = 5

  # Tell aurora to perform backup between this time as backup is quite heavy and it is better to choose a specific time where users don't use the database
  preferred_backup_window = "07:00-09:00"

  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name

  skip_final_snapshot  = false
  final_snapshot_identifier = "aurora-final-snapshot"

  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]

  storage_encrypted = true

  tags = {
    Name = "MyDB"
  }
}

resource "aws_rds_cluster_instance" "writer" {
  identifier = "aurora-writer"
  cluster_identifier = aws_rds_cluster.my_db.id
  instance_class = "db.t3.medium"
  engine = aws_rds_cluster.my_db.engine
  publicly_accessible = false

  tags = {
    Name = "Aurora Writer"
  }
}

resource "aws_rds_cluster_instance" "readers" {
  count = 2

  identifier = "aurora-reader-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.my_db.id
  instance_class = "db.t3.medium"
  engine = aws_rds_cluster.my_db.engine
  publicly_accessible = false

  tags = {
    Name = "Aurora Reader ${count.index + 1}"
  }
}

# Define the Application Auto Scaling Target
resource "aws_appautoscaling_target" "aurora_replica_target" {
  max_capacity       = 15
  min_capacity       = 1
  resource_id        = "cluster:${aws_rds_cluster.my_db.id}"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  service_namespace  = "rds"
}

# Define the Target Tracking Scaling Policy
resource "aws_appautoscaling_policy" "aurora_cpu_scaling_policy" {
  name               = "aurora-reader-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.aurora_replica_target.resource_id
  scalable_dimension = aws_appautoscaling_target.aurora_replica_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.aurora_replica_target.service_namespace

  target_tracking_scaling_policy_configuration {
    # Scale when average CPU hits 70%
    target_value       = 70.0    
    # Wait 5 minutes before removing a replica
    scale_in_cooldown  = 300                        
    # Wait 3 minutes before adding a replica
    scale_out_cooldown = 180                        

    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }
  }
}

# TRY TO SEE IF WE CAN RETRIEVE AND SAVE THE PASSWORD IN SECRETS MANAGER.
# TRY TO LOOK AT THE RDS PROXY.