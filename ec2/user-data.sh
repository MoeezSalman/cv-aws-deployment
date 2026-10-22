#!/bin/bash
set -euxo pipefail

BUCKET="cv-23l-3000"
PREFIX="site"
AWS_REGION="ap-southeast-2"

# Install the web server and AWS CLI.
dnf install -y httpd awscli
systemctl enable --now httpd

cat > /etc/cv-sync.conf <<EOF
BUCKET="${BUCKET}"
PREFIX="${PREFIX}"
AWS_REGION="${AWS_REGION}"
EOF
chmod 600 /etc/cv-sync.conf

# Keep the bootstrap self-contained: EC2 user data cannot assume that the GitHub
# repository has already been copied onto the instance.
cat > /usr/local/bin/sync-cv.sh <<'SYNC_SCRIPT'
#!/bin/bash
set -u
CONFIG_FILE="/etc/cv-sync.conf"
LOG_FILE="/var/log/cv-sync.log"
WEB_ROOT="/var/www/html"
log_result() { printf '{"time":"%s","result":"%s"}\\n' "$(date -Is)" "$1" >> "$LOG_FILE"; }
if [[ ! -f "$CONFIG_FILE" ]]; then log_result "FAILED: missing config"; exit 1; fi
source "$CONFIG_FILE"
TOKEN="$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")" || { log_result "FAILED: IMDSv2 token"; exit 1; }
INSTANCE_ID="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)" || { log_result "FAILED: instance ID"; exit 1; }
if aws s3 cp "s://${BUCKET}/${PREFIX}/" "$WEB_ROOT/" --recursive --region "${AWS_REGION}"; then
  if [[ -f "$WEB_ROOT/index.html" ]]; then sed -i "s|{{HOSTED_ON}}|EC2 ${INSTANCE_ID}|g" "$WEB_ROOT/index.html"; fi
  chown -R apache:apache "$WEB_ROOT"
  log_result "SUCCESS instance=${INSTANCE_ID}"
else
  log_result "FAILED instance=${INSTANCE_ID} s3-copy"
  exit 1
fi
SYNC_SCRIPT
chmod 0755 /usr/local/bin/sync-cv.sh

cat > /etc/systemd/system/cv-sync.service <<'EOF'
[Unit]
Description=Sync CV website files from private S3 bucket
[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync-cv.sh
EOF

cat > /etc/systemd/system/cv-sync.timer <<'EOF'
[Unit]
Description=Synchronize CV website from S3 every five minutes
[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
AccuracySec=30s
Unit=cv-sync.service
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl start cv-sync.service
systemctl enable --now cv-sync.timer
