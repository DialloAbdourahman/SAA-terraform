variable "aws_region" {
  description = "The AWS region to use"
  type        = string
}

variable "ubuntu_ami_id" {
  description = "The AMI to use for the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "The instance type to use for the EC2 instance"
  type        = string
}

variable "key_name" {
  description = "The name of the key pair to use for the EC2 instance"
  type        = string
}