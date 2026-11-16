#!/bin/bash
# Catalogue install, translated from roles/catalogue and roles/common.
# The systemd unit name stays catalogue and the process listens on port 8002.
# component=${component_name} catalogue=${catalogue_host} mysql=${mysql_host}
# Schema load follows the Ansible probes: schema.sql and app-user.sql run only
# when the database or user is missing. master-data.sql runs on every boot.
set -euo pipefail
exec > >(tee /var/log/roboshop-user-data.log) 2>&1

if ! id appuser >/dev/null 2>&1; then
  useradd --system --shell /bin/false --home-dir /app --create-home appuser
fi

rm -rf /app
mkdir -p /app
dnf install -y golang git mysql8.4 unzip
curl -fsSL -o /tmp/${component_name}.zip "${artifact_url}"
unzip -o /tmp/${component_name}.zip -d /app

cd /app

# Configure Go environment
export HOME=/root
export GOPATH=/root/go
export GOMODCACHE=/root/go/pkg/mod
export GOCACHE=/root/.cache/go-build

mkdir -p "$GOMODCACHE" "$GOCACHE"

go mod tidy
CGO_ENABLED=0 go build -o /app/${component_name} .

for attempt in $(seq 1 90); do
  if mysql -h "${mysql_host}" -u root -pRoboShop@1 -e "SELECT 1" >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 90 ]; then
    echo "MySQL at ${mysql_host} did not accept connections" >&2
    exit 1
  fi
  sleep 10
done

if mysql -h "${mysql_host}" -u root -pRoboShop@1 -e "USE catalogue" >/dev/null 2>&1; then
  catalogue_db_present=1
else
  catalogue_db_present=0
fi

catalogue_user_count="$(mysql -h "${mysql_host}" -u root -pRoboShop@1 -Nse "SELECT COUNT(*) FROM mysql.user WHERE User='catalogue' AND Host='%'" | tr -d '[:space:]')"

if [ "$catalogue_db_present" -eq 0 ]; then
  mysql -h "${mysql_host}" -u root -pRoboShop@1 < /app/db/schema.sql
fi
if [ "$catalogue_user_count" = "0" ]; then
  mysql -h "${mysql_host}" -u root -pRoboShop@1 < /app/db/app-user.sql
fi
mysql -h "${mysql_host}" -u root -pRoboShop@1 < /app/db/master-data.sql

chown -R appuser:appuser /app
chmod -R o-rwx /app

cat > /etc/systemd/system/${component_name}.service <<EOF
[Unit]
Description=RoboShop Catalogue Service
After=network.target

[Service]
Type=simple
User=appuser
WorkingDirectory=/app
ExecStart=/app/${component_name}
Restart=on-failure
RestartSec=10
SyslogIdentifier=${component_name}

Environment=MYSQL_HOST=${mysql_host}
Environment=MYSQL_USER=catalogue
Environment=MYSQL_PASSWORD=RoboShop@1
Environment=MYSQL_DATABASE=catalogue
Environment=PORT=8002

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${component_name}
systemctl restart ${component_name}
