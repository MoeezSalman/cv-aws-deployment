\
#!/usr/bin/env bash
set -u

if [[ "$#" -ne 3 ]]; then
  echo "Usage: $0 <bucket-name> <ec2-address> <lambda-function-url>"
  exit 1
fi

BUCKET="$1"
EC2_ADDRESS="${2%/}"
LAMBDA_ADDRESS="${3%/}"
REGION="ap-southeast-2"
EC2_ROLE="cv-ec2-role-23l-3000"
LAMBDA_ROLE="cv-lambda-role-23l-3000"
INSTANCE_NAME="cv-ec2-23l-3000"
FUNCTION_NAME="cv-func-23l-3000"
OUT="evidence.txt"
: > "$OUT"

section() { printf '\n== %s ==\n' "$1" >> "$OUT"; }
run() {
  local title="$1"; shift
  section "$title"
  "$@" >> "$OUT" 2>&1 || echo "COMMAND FAILED (exit $?)" >> "$OUT"
}

section "caller"
aws sts get-caller-identity >> "$OUT" 2>&1 || echo "COMMAND FAILED" >> "$OUT"

section "public-access"
aws s3api get-public-access-block --bucket "$BUCKET" --region "$REGION" >> "$OUT" 2>&1 || echo "COMMAND FAILED" >> "$OUT"

section "versioning"
aws s3api get-bucket-versioning --bucket "$BUCKET" --region "$REGION" >> "$OUT" 2>&1 || echo "COMMAND FAILED" >> "$OUT"

section "objects"
aws s3 ls "s3://${BUCKET}/site/" --recursive --human-readable --summarize --region "$REGION" >> "$OUT" 2>&1 || echo "COMMAND FAILED" >> "$OUT"

section "ec2-policy"
aws iam list-role-policies --role-name "$EC2_ROLE" >> "$OUT" 2>&1 || echo "COMMAND FAILED listing inline policies" >> "$OUT"
for policy in $(aws iam list-role-policies --role-name "$EC2_ROLE" --query 'PolicyNames[]' --output text 2>/dev/null); do
  echo "-- Inline policy: $policy --" >> "$OUT"
  aws iam get-role-policy --role-name "$EC2_ROLE" --policy-name "$policy" >> "$OUT" 2>&1 || echo "COMMAND FAILED" >> "$OUT"
done

section "lambda-policy"
aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE" >> "$OUT" 2>&1 || echo "COMMAND FAILED listing attached policies" >> "$OUT"
aws iam list-role-policies --role-name "$LAMBDA_ROLE" >> "$OUT" 2>&1 || echo "COMMAND FAILED listing inline policies" >> "$OUT"
for policy in $(aws iam list-role-policies --role-name "$LAMBDA_ROLE" --query 'PolicyNames[]' --output text 2>/dev/null); do
  echo "-- Inline policy: $policy --" >> "$OUT"
  aws iam get-role-policy --role-name "$LAMBDA_ROLE" --policy-name "$policy" >> "$OUT" 2>&1 || echo "COMMAND FAILED" >> "$OUT"
done

section "security-group"
INSTANCE_ID="$(aws ec2 describe-instances --region "$REGION" --filters "Name=tag:Name,Values=${INSTANCE_NAME}" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)"
if [[ -n "$INSTANCE_ID" && "$INSTANCE_ID" != "None" ]]; then
  SG_IDS="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text 2>/dev/null)"
  for sg in $SG_IDS; do aws ec2 describe-security-groups --region "$REGION" --group-ids "$sg" >> "$OUT" 2>&1 || echo "COMMAND FAILED" >> "$OUT"; done
else
  echo "Could not find running instance tagged Name=$INSTANCE_NAME" >> "$OUT"
fi

section "instance"
aws ec2 describe-instances --region "$REGION" --filters "Name=tag:Name,Values=${INSTANCE_NAME}" --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,State:State.Name,MetadataOptions:MetadataOptions,Profile:IamInstanceProfile.Arn,PublicIp:PublicIpAddress,Tags:Tags}' >> "$OUT" 2>&1 || echo "COMMAND FAILED" >> "$OUT"

section "endpoints"
for url in "$EC2_ADDRESS/" "$EC2_ADDRESS/style.css" "$EC2_ADDRESS/cv.pdf" "$LAMBDA_ADDRESS/" "$LAMBDA_ADDRESS/style.css" "$LAMBDA_ADDRESS/cv.pdf" "$LAMBDA_ADDRESS/anything" "https://${BUCKET}.s3.${REGION}.amazonaws.com/site/index.html"; do
  echo "-- $url --" >> "$OUT"
  curl -sS -o /dev/null -w 'status=%{http_code} content_type=%{content_type}\n' "$url" >> "$OUT" 2>&1 || echo "CURL FAILED" >> "$OUT"
done

section "lambda-logs"
aws logs tail "/aws/lambda/${FUNCTION_NAME}" --since 1h --format short --region "$REGION" >> "$OUT" 2>&1 || echo "COMMAND FAILED" >> "$OUT"

section "log-retention"
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${FUNCTION_NAME}" --region "$REGION" --query 'logGroups[].{logGroupName:logGroupName,retentionInDays:retentionInDays}' >> "$OUT" 2>&1 || echo "COMMAND FAILED" >> "$OUT"

echo "DONE"
