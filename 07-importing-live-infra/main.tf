provider "aws" {
  region = "eu-north-1"
}

resource "aws_instance" "initial_instance" {
  ami           = "ami-0974a2c5ddf10f442"
  instance_type = "t3.micro"
  associate_public_ip_address = true

  tags = {
    Name = "Terraform created instance"
  }
}

resource "aws_instance" "live_imported_ec2" {
  ami           = "ami-0ac1f955d6e62f3f1"
  instance_type = "t3.small"
  associate_public_ip_address = true
  vpc_security_group_ids = ["sg-0aee53ebc0b4e06c0"]
  subnet_id = "subnet-08adaf302030711dd"
  user_data_replace_on_change = false

  tags = {
    Name = "Terraform imported instance"
  }
}