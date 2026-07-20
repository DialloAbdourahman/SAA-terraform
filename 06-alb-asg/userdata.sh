#!/bin/bash

apt-get update
apt-get install -y apache2

systemctl enable apache2
systemctl start apache2

mkdir -p /var/www/html/api/auth

cat > /var/www/html/api/auth/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Auth Service</title>
</head>
<body>
    <h1>Auth Service API New Very New</h1>
    <p><strong>Hostname:</strong> $(hostname -f)</p>
</body>
</html>
EOF