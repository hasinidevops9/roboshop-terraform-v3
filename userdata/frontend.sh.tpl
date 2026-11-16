#!/bin/bash
# Frontend install, translated from roles/frontend in roboshop-ansible.
# Nginx serves the static export on port 80 and proxies /api/catalogue/ to catalogue.
# component=${component_name} catalogue=${catalogue_host} mysql=${mysql_host}
set -euo pipefail
exec > >(tee /var/log/roboshop-user-data.log) 2>&1

dnf install -y nginx git unzip curl

systemctl enable nginx
systemctl start nginx

curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs

rm -rf /tmp/frontend
mkdir -p /tmp/frontend
curl -fsSL -o /tmp/${component_name}.zip "${artifact_url}"
unzip -o /tmp/${component_name}.zip -d /tmp/frontend
cd /tmp/frontend
npm install
npm run build

rm -rf /usr/share/nginx/html
mkdir -p /usr/share/nginx/html
cp -a /tmp/frontend/out/. /usr/share/nginx/html/
chown -R root:root /usr/share/nginx/html

cat > /etc/nginx/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        listen 80;
        server_name _;
        root /usr/share/nginx/html;
        index index.html;

        location = /health {
            default_type text/plain;
            access_log off;
            return 200 'OK';
        }

        location /api/catalogue/ {
            rewrite ^/api/catalogue/(.*)$ /$1 break;
            proxy_pass http://${catalogue_host}:8002;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        location / {
            try_files $uri $uri/index.html $uri.html /index.html;
        }

        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
            expires 7d;
            add_header Cache-Control "public";
        }
    }
}
EOF

nginx -t
systemctl restart nginx
