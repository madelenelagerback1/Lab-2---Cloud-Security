
#!/bin/bash
set -euo pipefail

# ==========================================
# Task 2.1 - AWS Resource Cleanup
# Cloud Security D7078E
#
# Run from Git Bash:
# bash Lab2_Cleanup.sh
#
# DRY_RUN=true  -> Preview only
# DRY_RUN=false -> Delete after confirmation
# ==========================================

# Configuration
REGION="eu-north-1"


export AWS_PAGER=""

SG_NAME="Lab2-SecurityGroup"
ROLE_NAME="Lab2EC2Role"
POLICY_NAME="Lab2S3Policy"
INSTANCE_PROFILE="Lab2EC2Profile"
INSTANCE_TAG="Lab2-EC2"
DRY_RUN=false

# ==========================================
# Step 1 - Identify AWS environment
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
    echo "ERROR: No default VPC found."
    exit 1
fi

BUCKET_NAME="d7078e-lab2-storage-${ACCOUNT_ID}"

POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"

SSM_POLICY_ARN="arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

PROFILE_ARN="arn:aws:iam::$ACCOUNT_ID:instance-profile/$INSTANCE_PROFILE"

echo "=================================="
echo "Task 2.1 - AWS Cleanup"
echo "=================================="
echo "AWS account: $ACCOUNT_ID"
echo "Region: $REGION"
echo "VPC: $VPC_ID"
echo "Bucket: $BUCKET_NAME"
echo "Security group: $SG_NAME"
echo "IAM role: $ROLE_NAME"
echo "IAM policy: $POLICY_NAME"
echo "Instance profile: $INSTANCE_PROFILE"
echo "Dry run: $DRY_RUN"

# ==========================================
# Step 2 - Find lab resources
# ==========================================

echo ""
echo "Checking existing lab resources..."

SG_ID=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters \
      "Name=group-name,Values=$SG_NAME" \
      "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[0].GroupId" \
    --output text)

ROLE_EXISTS=false
POLICY_EXISTS=false
PROFILE_EXISTS=false
BUCKET_EXISTS=false

if aws iam get-role \
    --role-name "$ROLE_NAME" \
    >/dev/null 2>&1; then
    ROLE_EXISTS=true
fi

if aws iam get-policy \
    --policy-arn "$POLICY_ARN" \
    >/dev/null 2>&1; then
    POLICY_EXISTS=true
fi

if aws iam get-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE" \
    >/dev/null 2>&1; then
    PROFILE_EXISTS=true
fi

if aws s3api head-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    >/dev/null 2>&1; then
    BUCKET_EXISTS=true
fi

# Find instances using the lab instance profile.

INSTANCE_IDS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters \
      "Name=iam-instance-profile.arn,Values=$PROFILE_ARN" \
      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

# ==========================================
# Step 3 - Show cleanup summary
# ==========================================

echo ""
echo "=================================="
echo "Cleanup summary"
echo "=================================="
echo "Security group: $SG_ID"
echo "S3 bucket exists: $BUCKET_EXISTS"
echo "IAM role exists: $ROLE_EXISTS"
echo "IAM policy exists: $POLICY_EXISTS"
echo "Instance profile exists: $PROFILE_EXISTS"
echo "EC2 instances: ${INSTANCE_IDS:-None}"

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "DRY RUN: No resources have been deleted."
    echo "Review the resources before enabling cleanup."
    exit 0
fi

# ==========================================
# Step 4 - Safety checks
# ==========================================

echo ""
echo "Verifying lab resources..."

# Require the complete lab resource set.
# This avoids deleting unrelated resources
# that happen to share a lab resource name.

if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ] || \
   [ "$ROLE_EXISTS" != true ] || \
   [ "$POLICY_EXISTS" != true ] || \
   [ "$PROFILE_EXISTS" != true ] || \
   [ "$BUCKET_EXISTS" != true ]; then

    echo "ERROR: Lab resources are missing."
    echo "Automatic cleanup cancelled."
    echo "Review remaining resources manually."
    exit 1
fi

# Verify the security group name and VPC.

SG_DETAILS=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --group-ids "$SG_ID" \
    --query "SecurityGroups[0].[GroupName,VpcId]" \
    --output text)

read -r ACTUAL_SG_NAME ACTUAL_VPC_ID <<< "$SG_DETAILS"

if [ "$ACTUAL_SG_NAME" != "$SG_NAME" ] || \
   [ "$ACTUAL_VPC_ID" != "$VPC_ID" ]; then
    echo "ERROR: Security group verification failed."
    exit 1
fi

# Verify instance profile contains the lab role.

PROFILE_ROLES=$(aws iam get-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE" \
    --query "InstanceProfile.Roles[].RoleName" \
    --output text)

if [ "$PROFILE_ROLES" != "$ROLE_NAME" ]; then
    echo "ERROR: Unexpected instance profile role."
    exit 1
fi

# Verify IAM role has only expected managed policies.
ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
    --role-name "$ROLE_NAME" \
    --query "AttachedPolicies[].PolicyArn" \
    --output text | tr -d '\r')

for ARN in $ATTACHED_POLICIES; do
    if [ "$ARN" != "$POLICY_ARN" ] && \
       [ "$ARN" != "$SSM_POLICY_ARN" ]; then
        echo "ERROR: Unexpected IAM policy: $ARN"
        exit 1
    fi
done

# Verify custom policy is attached to the lab role.

if ! printf '%s\n' "$ATTACHED_POLICIES" |
    tr '\t' '\n' |
    grep -Fxq "$POLICY_ARN"; then

    echo "ERROR: Lab S3 policy is not attached."
    exit 1
fi

# Reject IAM roles with inline policies.

INLINE_POLICIES=$(aws iam list-role-policies \
    --role-name "$ROLE_NAME" \
    --query "PolicyNames" \
    --output text)

if [ -n "$INLINE_POLICIES" ] && \
   [ "$INLINE_POLICIES" != "None" ]; then
    echo "ERROR: IAM role has inline policies."
    exit 1
fi

# Verify the custom policy is not used elsewhere.

ATTACHMENT_COUNT=$(aws iam get-policy \
    --policy-arn "$POLICY_ARN" \
    --query "Policy.AttachmentCount" \
    --output text)

if [ "$ATTACHMENT_COUNT" != "1" ]; then
    echo "ERROR: Unexpected IAM policy attachment count."
    exit 1
fi

# Reject versioned S3 buckets.

VERSIONING_STATUS=$(aws s3api get-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --query "Status" \
    --output text)

if [ "$VERSIONING_STATUS" = "Enabled" ] || \
   [ "$VERSIONING_STATUS" = "Suspended" ]; then
    echo "ERROR: S3 bucket has versioning history."
    echo "Manual review required."
    exit 1
fi

# Verify EC2 instances have the correct
# lab name, security group and instance profile.

if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then

    read -r -a INSTANCE_ARRAY <<< "$INSTANCE_IDS"

    for ID in "${INSTANCE_ARRAY[@]}"; do

        INSTANCE_NAME=$(aws ec2 describe-instances \
            --region "$REGION" \
            --instance-ids "$ID" \
            --query \
              "Reservations[0].Instances[0].Tags[?Key=='Name'].Value | [0]" \
            --output text)

        INSTANCE_SG=$(aws ec2 describe-instances \
            --region "$REGION" \
            --instance-ids "$ID" \
            --query \
              "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
            --output text)

        INSTANCE_PROFILE_ARN=$(aws ec2 describe-instances \
            --region "$REGION" \
            --instance-ids "$ID" \
            --query \
              "Reservations[0].Instances[0].IamInstanceProfile.Arn" \
            --output text)

        if [ "$INSTANCE_NAME" != "$INSTANCE_TAG" ] || \
           [ "$INSTANCE_SG" != "$SG_ID" ] || \
           [ "$INSTANCE_PROFILE_ARN" != "$PROFILE_ARN" ]; then

            echo "ERROR: Instance verification failed: $ID"
            echo "Cleanup cancelled."
            exit 1
        fi

        echo "Verified lab instance: $ID"
    done
fi

echo "Resource checks completed."

# ==========================================
# Step 5 - Confirm deletion
# ==========================================

echo ""
echo "WARNING: This will permanently delete"
echo "the listed AWS lab resources."
echo "EC2 instances and S3 objects may be lost."

read -r -p "Type DELETE to continue: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

# ==========================================
# Step 6 - Terminate EC2 instances
# ==========================================

if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then

    echo "Terminating EC2 instances..."

    aws ec2 terminate-instances \
        --instance-ids "${INSTANCE_ARRAY[@]}" \
        --region "$REGION"

    aws ec2 wait instance-terminated \
        --instance-ids "${INSTANCE_ARRAY[@]}" \
        --region "$REGION"

    echo "EC2 instances terminated."
else
    echo "No active lab EC2 instances."
fi

# ==========================================
# Step 7 - Delete instance profile
# ==========================================

echo "Removing instance profile..."

aws iam remove-role-from-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE" \
    --role-name "$ROLE_NAME"

aws iam delete-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE"

echo "Instance profile deleted."

# ==========================================
# Step 8 - Delete IAM role
# ==========================================

echo "Removing IAM role..."

for ARN in $ATTACHED_POLICIES; do
    aws iam detach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "$ARN"
done

aws iam delete-role \
    --role-name "$ROLE_NAME"

echo "IAM role deleted."

# ==========================================
# Step 9 - Delete custom IAM policy
# ==========================================

echo "Deleting custom IAM policy..."

aws iam delete-policy \
    --policy-arn "$POLICY_ARN"

echo "IAM policy deleted."

# ==========================================
# Step 10 - Delete security group
# ==========================================

echo "Deleting security group: $SG_ID"

aws ec2 delete-security-group \
    --group-id "$SG_ID" \
    --region "$REGION"

echo "Security group deleted."

# ==========================================
# Step 11 - Delete S3 bucket
# ==========================================

echo "Emptying S3 bucket..."

aws s3 rm "s3://$BUCKET_NAME" \
    --recursive \
    --region "$REGION"

aws s3api delete-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION"

echo "S3 bucket deleted."

# ==========================================
# Step 12 - Cleanup completed
# ==========================================

echo ""
echo "=================================="
echo "Task 2.1 cleanup completed."
echo "=================================="
