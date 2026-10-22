\
#!/bin/bash
set -u

CONFIG_FILE="/etc/cv-sync.conf"
LOG_FILE="/var/log/cv-sync.log"
WEB_ROOT="/var/www/html"

log_result() {
  printf '{"time":"%s","result":"%s"}\n' "$(date -Is)" "$1" >> "$LOG_FILE"
}

if [[ ! -f "$CONFIG_FILE" ]]; then
  log_result "FAILED: missing $CONFIG_FILE"
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

if [[ -z "${BUCKET:-}" || -z "${PREFIX:-}" ]]; then
  log_result "FAILED: BUCKET or PREFIX not configured"
  exit 1
fi

TOKEN="$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)" || {
  log_result "FAILED: unable to get IMDSv2 token"
  exit 1
}
INSTANCE_ID="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null)" || {
  log_result "FAILED: unable to read instance ID"
  exit 1
}

if aws s3 cp "s3://${BUCKET}/${PREFIX}/" "$WEB_ROOT/" --recursive --region "${AWS_REGION:-ap-southeast-2}"; then
  if [[ -f "$WEB_ROOT/index.html" ]]; then
    sed -i "s|{{HOSTED_ON}}|EC2 ${INSTANCE_ID}|g" "$WEB_ROOT/index.html"
  fi
  chown -R apache:apache "$WEB_ROOT"
  log_result "SUCCESS instance=${INSTANCE_ID}"
else
  log_result "FAILED instance=${INSTANCE_ID} s3-copy"
  exit 1
fi
