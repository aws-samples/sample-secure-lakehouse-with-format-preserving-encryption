#!/usr/bin/env bash
# =============================================================================
# Bootstrap Script — Creates the S3 state bucket and generates backend.hcl
# This is a one-time prerequisite before running `terraform init`.
# Works on AWS CloudShell (uploaded) or locally with AWS CLI configured.
#
# Usage: ./scripts/bootstrap.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Color codes for output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
STATE_KEY="enc-blog-infrastructure/terraform.tfstate"

# ---------------------------------------------------------------------------
# Prompt user for AWS region
# ---------------------------------------------------------------------------
read -rp "Enter AWS region (press Enter for us-east-1): " REGION
REGION="${REGION:-us-east-1}"

# ---------------------------------------------------------------------------
# Resolve AWS Account ID
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Resolving AWS Account ID...${NC}"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

if [[ -z "$AWS_ACCOUNT_ID" ]]; then
  echo -e "${RED}✗ Failed to resolve AWS Account ID. Ensure AWS CLI is configured.${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Account ID: ${AWS_ACCOUNT_ID}${NC}"

# ---------------------------------------------------------------------------
# Construct bucket name
# ---------------------------------------------------------------------------
BUCKET_NAME="enc-blog-s3-tf-state-bucket-${AWS_ACCOUNT_ID}"

echo -e "${YELLOW}Bucket name: ${BUCKET_NAME}${NC}"
echo -e "${YELLOW}Region:      ${REGION}${NC}"
echo -e "${YELLOW}State key:   ${STATE_KEY}${NC}"

# ---------------------------------------------------------------------------
# Idempotent check: does the bucket already exist?
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Checking if bucket '${BUCKET_NAME}' already exists...${NC}"

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo -e "${GREEN}✓ Bucket '${BUCKET_NAME}' already exists. Skipping creation.${NC}"
else
  # -------------------------------------------------------------------------
  # Create the S3 bucket
  # us-east-1 does not accept --create-bucket-configuration
  # -------------------------------------------------------------------------
  echo -e "${YELLOW}Creating bucket '${BUCKET_NAME}' in region '${REGION}'...${NC}"

  if aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION"; then
    echo -e "${GREEN}✓ Bucket '${BUCKET_NAME}' created successfully.${NC}"
  else
    echo -e "${RED}✗ Failed to create bucket '${BUCKET_NAME}'.${NC}"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Enable versioning
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Enabling versioning on '${BUCKET_NAME}'...${NC}"

if aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled; then
  echo -e "${GREEN}✓ Versioning enabled.${NC}"
else
  echo -e "${RED}✗ Failed to enable versioning.${NC}"
  exit 1
fi

# ---------------------------------------------------------------------------
# Block all public access
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Blocking all public access on '${BUCKET_NAME}'...${NC}"

if aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"; then
  echo -e "${GREEN}✓ All public access blocked.${NC}"
else
  echo -e "${RED}✗ Failed to block public access.${NC}"
  exit 1
fi

# ---------------------------------------------------------------------------
# Generate backend.hcl
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_FILE="${PROJECT_ROOT}/backend.hcl"

echo -e "${YELLOW}Generating backend.hcl...${NC}"

cat > "$BACKEND_FILE" <<EOF
bucket       = "${BUCKET_NAME}"
key          = "${STATE_KEY}"
region       = "${REGION}"
encrypt      = true
use_lockfile = true
EOF

echo -e "${GREEN}✓ backend.hcl written at ${BACKEND_FILE}${NC}"

# ---------------------------------------------------------------------------
# Create required directories for Terraform plan (not committed to git)
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Creating required build directories...${NC}"
mkdir -p "${PROJECT_ROOT}/modules/vault-transform-service/assets/fpe_layer/python"
touch "${PROJECT_ROOT}/modules/vault-transform-service/assets/fpe_layer/python/__init__.py"
echo -e "${GREEN}✓ FPE layer directory created${NC}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  State bucket '${BUCKET_NAME}' is ready in region '${REGION}'${NC}"
echo -e "${GREEN}  • Versioning: Enabled${NC}"
echo -e "${GREEN}  • Public access: Blocked${NC}"
echo -e "${GREEN}  • backend.hcl: Generated${NC}"
echo -e "${GREEN}  • FPE layer directory: Created${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Next step:"
echo "  terraform init -backend-config=backend.hcl"
