# Host Your CV on AWS — Roll No. 23L-3000

> Before submission: replace any TODOs with your real output, add `site/cv.pdf`, confirm every AWS resource name/region, and run the evidence script after Lambda is deployed. Never commit credentials or access keys.

## Live deployments

- **EC2:** http://3.106.255.92/
- **Lambda Function URL:** TODO — create the function and paste its public HTTPS Function URL here.
- **S3 direct object:** https://cv-23l-3000.s3.ap-southeast-2.amazonaws.com/site/index.html (must return Access Denied)

## Architecture

```text
                          Public visitors
                           /            \
                          /              \
               HTTP :80 /                \ HTTPS Function URL
                       v                  v
               EC2 / Apache           AWS Lambda
               cv-ec2-23l-3000        cv-func-23l-3000
                       |                  |
               EC2 IAM role          Lambda IAM role
                       |                  |
                       +--------+---------+
                                |
                         Private S3 bucket
                          cv-23l-3000/site/
                    index.html  style.css  cv.pdf
```

**EC2 path:** A visitor opens the EC2 public IPv4 address. Apache serves the local copy of `site/`, which the instance role syncs from the private S3 bucket every five minutes; the page footer is replaced with `EC2` and the running instance ID.

**Lambda path:** A visitor opens the public Lambda Function URL. The function reads the requested file from the same private S3 bucket using its execution role, replaces the footer for the HTML page, and returns the appropriate content type (including base64 encoding for the PDF).

## Files

- `site/`: the three website assets. Keep `{{HOSTED_ON}}` in the S3 copy of `index.html`; the two delivery paths replace it at response time.
- `ec2/user-data.sh`: EC2 bootstrap setup and systemd timer configuration.
- `ec2/sync-cv.sh`: copies the `site/` prefix to Apache's web root and logs each run.
- `lambda/app.py`: Lambda handler for `/`, `/index.html`, `/style.css`, `/cv.pdf`, and 404 paths.
- `iam/`: trust and permission policy JSON files for both roles.
- `collect-evidence.sh`: collects the required evidence into `evidence.txt`.

## IAM policy setup

The JSON files use bucket `cv-23l-3000` and roles `cv-ec2-role-23l-3000` / `cv-lambda-role-23l-3000`. Create the roles with the matching trust policy, then attach the matching permission policy as an inline policy. For Lambda, also attach the AWS managed policy `service-role/AWSLambdaBasicExecutionRole`. Do not add access keys.

## EC2 setup notes

1. Keep the EC2 instance name tag `Name=cv-ec2-23l-3000`, type `t2.micro` or `t3.micro`, and region `ap-southeast-2`.
2. Attach `cv-ec2-role-23l-3000` via an instance profile and require IMDSv2.
3. Allow inbound TCP 80 from `0.0.0.0/0`; allow TCP 22 only from your own IP `/32` or leave it closed. No other inbound rules.
4. The provided user-data script embeds the sync logic so it can bootstrap a new instance by itself. For an already-running instance, configure `/etc/cv-sync.conf`, copy `ec2/sync-cv.sh` to `/usr/local/bin/sync-cv.sh`, and create/enable the systemd service and timer as shown in the user-data script.
5. Verify with `systemctl status cv-sync.timer`, `sudo tail -n 10 /var/log/cv-sync.log`, and `curl -I http://3.106.255.92/style.css`.

## Lambda setup notes

1. Create `cv-func-23l-3000` in `ap-southeast-2`, runtime Python 3.13 (or latest available), handler `app.handler`, memory 128–256 MB, timeout 10 seconds.
2. Upload `lambda/app.py` as the function code. Set environment variables `BUCKET=cv-23l-3000` and `PREFIX=site`.
3. Use execution role `cv-lambda-role-23l-3000`, with `AWSLambdaBasicExecutionRole` and the inline S3 `GetObject` policy.
4. Create a Function URL with authentication type `NONE`. Confirm the console-created `lambda:InvokeFunctionUrl` / public invocation permission appears in the function's Permissions tab.
5. Set the log group `/aws/lambda/cv-func-23l-3000` retention to 7 days.
6. Test `/`, `/style.css`, `/cv.pdf`, and `/anything`; expected statuses are 200, 200, 200, and 404.

## Required evidence

Run this from the repository root in an environment with AWS CLI credentials configured for your account:

```bash
chmod +x collect-evidence.sh
./collect-evidence.sh cv-23l-3000 3.106.255.92 'PASTE_LAMBDA_FUNCTION_URL_HERE'
```

This writes `evidence.txt`. Commit the evidence file produced by your own run. It should have 11 sections: `caller`, `public-access`, `versioning`, `objects`, `ec2-policy`, `lambda-policy`, `security-group`, `instance`, `endpoints`, `lambda-logs`, and `log-retention`.

## Required README evidence to add before submission

### S3 write-denial test (paste actual terminal output)

From the EC2 instance, run `aws s3 rm s3://cv-23l-3000/site/__permission_test__.txt --region ap-southeast-2` and paste the actual terminal output here. This uses a deliberately nonexistent test key, not one of your real files. The command must return `AccessDenied`; do not grant write/delete permissions just to make this test work.

### Last 10 EC2 sync log lines (paste actual output)

TODO: Paste the output of `sudo tail -n 10 /var/log/cv-sync.log`. It should show at least three successful scheduled runs in a row.

## Written answers (each answer is at most five sentences)

1. **Why roles instead of access keys? What could go wrong if keys were in user data?**  
   Roles provide short-lived credentials through the AWS metadata/credential service and avoid storing long-lived secrets on the instance or in source code. Keys in user data may be exposed through instance metadata, console access, logs, backups, or anyone who can inspect the script. An exposed key could let an attacker access AWS resources until it is revoked.

2. **What happens when someone opens the S3 URL of `site/index.html` directly, and which setting causes it?**  
   The request should return `AccessDenied` because the bucket is private. The four S3 Block Public Access settings are enabled, and no public bucket policy or public ACL grants access.

3. **What is the public Function URL permission, and why is it acceptable for Lambda but not for the bucket?**  
   The Function URL configured with authentication type `NONE` has a resource-based permission that allows public callers to invoke the function URL. This is intentional because the function is the public web entry point and its code only reads the required site objects. The S3 bucket itself remains private, so visitors cannot browse or download its objects directly.

4. **Compare the two paths. What do you pay for when nobody visits, and what if traffic grows 100 times?**  
   EC2 can incur instance and storage charges while running even with no visitors. Lambda is billed mainly for invocations and execution time, although supporting resources and request volume may also incur charges. At much higher traffic, Lambda can scale automatically within account and service limits, while a single EC2 instance may become a bottleneck and need capacity changes.

5. **If you delete the EC2 instance, what do you lose and what do you still have?**  
   You lose the running web server, its public IPv4 address, and the local synchronized copy on that instance. The private S3 objects, Lambda deployment, IAM roles, and repository remain unless separately deleted. A replacement EC2 instance can be launched and resynchronized from S3.

## Adaptations

The shell scripts and Lambda handler in this repository were prepared as a starting implementation for this lab. Review, test, and understand every file before submission, and disclose any adaptation required by your course rules.
