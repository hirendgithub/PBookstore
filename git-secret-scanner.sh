#!/bin/bash

set -e
set -o pipefail

CLI="cx"
REPO_URL="$1"
BRANCH_NAME="$2"

if [ -z "$REPO_URL" ]; then
  echo " Error: REPO_URL not provided"
  exit 1
fi

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
mkdir -p report_output

# Configure AST CLI
cx configure set --prop-name 'cx_base_uri' --prop-value 'https://deu.ast.checkmarx.net/'
cx configure set --prop-name 'cx_base_auth_uri' --prop-value 'https://deu.iam.checkmarx.net/'
cx configure set --prop-name 'cx_tenant' --prop-value 'cx-cs-na-pspoc'
cx configure set --prop-name 'cx_apikey' --prop-value "eyJhbGciOiJIUzUxMiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICI0NmM5YThiYy0xYTliLTQyNjItOGRhNi1hM2M0"

# Run scan (outputs directly to ./report_output)
echo " Running Checkmarx scan..."
if ! cx scan create --project-name "ado-project" --branch "$BRANCH_NAME" \
  -s "$REPO_URL" --scan-types "sast, sca" \
  --report-format json --report-format summaryHTML \
  --output-name "ado-report" --output-path "./report_output" \
  --report-pdf-email hiren.soni46@yahoo.com --report-pdf-options sast \
  --ignore-policy --debug; then
  echo " cx scan failed"
  exit 1
fi

# Debug output to verify reports were created
echo " Listing contents of report_output:"
ls -lh report_output || echo " report_output directory not found"

echo " Searching for ado-report.* files..."
find . -type f -name "ado-report*"

# Install msmtp and mutt for email
echo "Installing msmtp and mutt..."
sudo apt-get update && sudo apt-get install -y msmtp msmtp-mta mutt

# Setup SMTP config
echo " Configuring email settings..."
cat <<EOF > ~/.msmtprc
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile ~/.msmtp.log

account gmail
host smtp.gmail.com
port 587
from hirendhakan8080@gmail.com
user hirendhakan8080@gmail.com
password ndmrjelrrioqoiuk

account default : gmail
EOF

chmod 600 ~/.msmtprc

# Send the report if it exists
REPORT_FILE="report_output/ado-report.summaryHTML"
if [[ -f "$REPORT_FILE" ]]; then
  echo "Sending report via email..."
  echo "This email includes an attachment of project summary." | mutt -s "Project Scan Summary" \
    -a "$REPORT_FILE" -- hiren.soni46@yahoo.com
  echo "Report sent successfully."
else
  echo "Report file not found at expected location: $REPORT_FILE"
  echo "Skipping email."
fi
