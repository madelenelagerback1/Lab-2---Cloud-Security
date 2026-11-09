
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# ==========================================
# Task 2.1 - AWS CLI Bash Script
# Cloud Security D7078E
# Steps (a)-(i)
# ==========================================

# Configuration
REGION="eu-north-1"
INSTANCE_TYPE="t3.micro"

export AWS_PAGER=""

SG_NAME="Lab2-SecurityGroup"
ROLE_NAME="Lab2EC2Role"
POLICY_NAME="Lab2S3Policy"
INSTANCE_PROFILE="Lab2EC2Profile"
INSTANCE_TAG="Lab2-EC2"

TRUST_POLICY_FILE="Lab2TrustPolicy.json"

# ==========================================
# Verify AWS environment
# ==========================================

ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account \
    --output text)

VPC_ID=$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters "Name=isDefault,Values=true" \
    --query "Vpcs[0].VpcId" \
    --output text)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
    echo "ERROR: No default VPC found in $REGION."
    exit 1
fi

PUBLIC_IP=$(curl -fsS -4 https://checkip.amazonaws.com)
PUBLIC_IP=$(echo "$PUBLIC_IP" | tr -d '\r\n')

if [[ ! "$PUBLIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "ERROR: Could not determine public IPv4 address."
    exit 1
fi

MY_IP="${PUBLIC_IP}/32"
BUCKET_NAME="d7078e-lab2-storage-${ACCOUNT_ID}"

if [ ! -f "$TRUST_POLICY_FILE" ]; then
    echo "ERROR: Missing $TRUST_POLICY_FILE"
    exit 1
fi

# Find the latest available Amazon Linux 2023 AMI.
# Uses EC2 describe-images instead of SSM.

AMI_ID=$(aws ec2 describe-images \
    --region "$REGION" \
    --owners amazon \
    --filters \
      "Name=name,Values=al2023-ami-2023.*-x86_64" \
      "Name=state,Values=available" \
    --query "sort_by(Images,&CreationDate)[-1].ImageId" \
    --output text)

if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
    echo "ERROR: No Amazon Linux 2023 AMI found."
    exit 1
fi

echo "=================================="
echo "Task 2.1 - AWS Deployment"
echo "=================================="
echo "AWS account: $ACCOUNT_ID"
echo "Region: $REGION"
echo "VPC: $VPC_ID"
echo "Bucket: $BUCKET_NAME"
echo "SSH allowed IP: $MY_IP"
echo "AMI: $AMI_ID"

# Check for existing resources to avoid overwriting
# or duplicating a previous deployment.

EXISTING_SG=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters \
      "Name=group-name,Values=$SG_NAME" \
      "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[0].GroupId" \
    --output text)

if [ "$EXISTING_SG" != "None" ] && [ -n "$EXISTING_SG" ]; then
    echo "ERROR: Lab security group already exists."
    echo "Security group: $EXISTING_SG"
    echo "Review existing resources before deployment."
    exit 1
fi

if aws iam get-role \
    --role-name "$ROLE_NAME" \
    >/dev/null 2>&1; then
    echo "ERROR: IAM role already exists."
    exit 1
fi

if aws iam get-policy \
    --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME" \
    >/dev/null 2>&1; then
    echo "ERROR: IAM policy already exists."
    exit 1
fi

if aws iam get-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE" \
    >/dev/null 2>&1; then
    echo "ERROR: Instance profile already exists."
    exit 1
fi

if aws s3api head-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" >/dev/null 2>&1; then
    echo "ERROR: S3 bucket already exists."
    exit 1
fi

# ==========================================
# Step (a) - Create security group
# ==========================================

SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Security group for Lab 2" \
    --vpc-id "$VPC_ID" \
    --region "$REGION" \
    --query "GroupId" \
    --output text)

echo "Security group created: $SG_ID"

# ==========================================
# Step (b) - Allow SSH from current IP
# ==========================================

aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr "$MY_IP" \
    --region "$REGION"

echo "SSH rule added for IP: $MY_IP"

# ==========================================
# Step (c) - Verify SSH rule
# ==========================================

aws ec2 describe-security-groups \
    --group-ids "$SG_ID" \
    --region "$REGION" \
    --query "SecurityGroups[0].IpPermissions" \
    --output json

echo "SSH rule verified."

# ==========================================
# Step (d) - Allow HTTP from anywhere
# ==========================================

aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr "0.0.0.0/0" \
    --region "$REGION"

aws ec2 describe-security-groups \
    --group-ids "$SG_ID" \
    --region "$REGION" \
    --query "SecurityGroups[0].IpPermissions" \
    --output json

echo "HTTP rule added and rules verified."

# ==========================================
# Step (e) - Create S3 bucket
# ==========================================

aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration \
      "LocationConstraint=$REGION"

echo "S3 bucket created: $BUCKET_NAME"

aws s3api head-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION"

echo "S3 bucket verified."

# ==========================================
# Step (f) - Create custom IAM policy
# ==========================================

# Generate the policy dynamically so that
# it references the correct S3 bucket.

S3_POLICY_FILE=$(mktemp)
trap 'rm -f "$S3_POLICY_FILE"' EXIT

cat > "$S3_POLICY_FILE" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::$BUCKET_NAME"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
    }
  ]
}
EOF

POLICY_ARN=$(aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "file://$S3_POLICY_FILE" \
    --query "Policy.Arn" \
    --output text)

echo "IAM policy created: $POLICY_ARN"

aws iam get-policy \
    --policy-arn "$POLICY_ARN"

# ==========================================
# Step (g) - Create IAM role
# ==========================================

aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document \
      "file://$TRUST_POLICY_FILE"

echo "IAM role created: $ROLE_NAME"

aws iam get-role \
    --role-name "$ROLE_NAME"

# ==========================================
# Step (h) - Attach S3 policy
# ==========================================

aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN"

echo "IAM policy attached to role."

aws iam list-attached-role-policies \
    --role-name "$ROLE_NAME"

echo "IAM role policy attachment verified."

# ==========================================
# Step (i) - Launch EC2 instance
# ==========================================

aws iam create-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE"

aws iam add-role-to-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE" \
    --role-name "$ROLE_NAME"

# Allow access through AWS Systems Manager.

aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn \
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

echo "Waiting for IAM configuration..."
sleep 30

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --security-group-ids "$SG_ID" \
    --iam-instance-profile "Name=$INSTANCE_PROFILE" \
    --region "$REGION" \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_TAG}]" \
    --query "Instances[0].InstanceId" \
    --output text)

echo "EC2 instance launched: $INSTANCE_ID"

aws ec2 wait instance-running \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION"

aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query \
      "Reservations[0].Instances[0].[InstanceId,State.Name,IamInstanceProfile.Arn]" \
    --output table

echo "=================================="
echo "Task 2.1 steps (a)-(i) completed."
echo "=================================="
