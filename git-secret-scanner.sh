#!/bin/bash

set -e
set -o pipefail

CLI="cx"
REPO_URL="$1"
BRANCH_NAME="$2"
ACCOUNT="$ACCOUNT"
HOST="$HOST"
PORT="$PORT"
SENDER_EMAIL="$SENDER_EMAIL"
SENDER_EMAIL_USERNAME="$SENDER_EMAIL_USERNAME"
SENDER_EMAIL_PASSWORD="$SENDER_EMAIL_PASSWORD"
ACCOUNT_DEFAULT="$ACCOUNT_DEFAULT"
RECIPIENT_EMAIL="$RECIPIENT_EMAIL"
CX_BASE_URL="$CX_BASE_URL"
CX_BASE_AUTH_URL="$CX_BASE_AUTH_URL"
CX_TENANT_NAME="$CX_TENANT_NAME"
CX_API_KEY="$CX_API_KEY"
 
if [ -z "$REPO_URL" ]; then
  echo " Error: REPO_URL not provided"
  exit 1
fi
echo -e "account: $ACCOUNT\nhost: $HOST\nport: $PORT\nfrom: $SENDER_EMAIL\nuser: $SENDER_EMAIL_USERNAME\npassword: $SENDER_EMAIL_PASSWORD"

echo " Repo URL: $REPO_URL"
echo " Branch Name: $BRANCH_NAME"

timestamp=$(date +"%d_%m_%Y_%H_%M_%S")
Report_name="demo_project_$timestamp"

# Clone repo
mkdir -p scanned_project
cd scanned_project
git clone "$REPO_URL"
cd "$(basename "$REPO_URL" .git)"

if [ -n "$BRANCH_NAME" ]; then
  git checkout "$BRANCH_NAME"
fi

# Go back to root for consistent output directory path
cd ../..

# Create output dir
sudo mkdir -m 755 report_output
sudo chmod -R 777 report_output

# Configure AST CLI
cx configure set --prop-name 'cx_base_uri' --prop-value '$CX_BASE_URL'
cx configure set --prop-name 'cx_base_auth_uri' --prop-value '$CX_BASE_AUTH_URL'
cx configure set --prop-name 'cx_tenant' --prop-value '$CX_TENANT_NAME'
cx configure set --prop-name 'cx_apikey' --prop-value "$CX_API_KEY"

# Run scan (outputs directly to ./report_output)
echo " Running Checkmarx scan..."
if ! cx scan create --project-name "ado-project" --branch "$BRANCH_NAME" \
  -s "$REPO_URL" --scan-types "sast" --sast-incremental \
  --report-format json --report-format summaryHTML \
  --output-name "$Report_name" --output-path "report_output" \
  --ignore-policy --debug; then
  echo " cx scan failed"
  exit 1
fi

# Debug output to verify reports were created
echo " Listing contents of report_output:"
ls -lh report_output || echo " report_output directory not found"

echo " Searching for $Report_name.* files..."
find report_output -type f -name "$Report_name.*"

# Install msmtp and mutt for email
echo " Installing msmtp and mutt..."
sudo apt-get update && sudo apt-get install -y msmtp msmtp-mta mutt

# Setup SMTP config
echo " Configuring email settings..."
cat <<EOF > ~/.msmtprc
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile ~/.msmtp.log

account $ACCOUNT
host $HOST
port $PORT
from $SENDER_EMAIL
user $SENDER_EMAIL_USERNAME
password $SENDER_EMAIL_PASSWORD

account default : $ACCOUNT_DEFAULT
EOF

chmod 600 ~/.msmtprc

# === Smart Report Detection and Email ===
echo " Looking for any summaryHTML report file in report_output/"
REPORT_FILE=$(find report_output -type f -name "*.html" | head -n 1)


if [[ -f "$REPORT_FILE" ]]; then
 echo " Sending report via email: $REPORT_FILE"
  echo "This email includes an attachment of project summary." | mutt -s "Project Scan Summary" \
   -a "$REPORT_FILE" -- $RECIPIENT_EMAIL
  echo " Report sent successfully."
else
  echo
  echo " Report file not found at expected location: report_output/html"
  echo "Skipping email."
fi