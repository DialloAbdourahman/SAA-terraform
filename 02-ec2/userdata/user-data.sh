#!/bin/bash
# Use this for your Ubuntu EC2 user data script
apt-get update -y
apt-get install -y apache2
systemctl start apache2
systemctl enable apache2
echo "<h1>Hello World from $(hostname -f)</h1>" | tee /var/www/html/index.html