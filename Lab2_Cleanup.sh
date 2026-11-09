
#!/bin/bash
set -euo pipefail

# Task 2.1 - AWS Resource Cleanup
# Cloud Security D7078E
#
# Run from Git Bash:
# bash Lab2_Cleanup.sh
#
# DRY_RUN=true  -> Preview only
# DRY_RUN=false -> Require confirmation before deletion

# ==========================================
# Configuration
# ==========================================

REGION="eu-north-1"
EXPECTED_ACCOUNT_ID="692701543827"

VPC_ID="vpc-0e773d5d243e2af90"
BUCKET_NAME="d7078e-lab2-storage-20261109-ml"

SG_NAME="Lab2-SecurityGroup"
ROLE_NAME="Lab2EC2Role"
POLICY_NAME="Lab2S3Policy"
INSTANCE_PROFILE="Lab2EC2Profile"
INSTANCE_TAG="Lab2-EC2"

DRY_RUN=true

# Known original lab security group.
EXPECTED_SG_ID="sg-0d05e1376286b618e"

# AWS CLI output settings.
export AWS_PAGER=""

# ==========================================
# Step 1 - Verify AWS account
# ==========================================

echo "=================================="
echo "Task 2.1 - AWS Cleanup"
echo "=================================="

ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account \
    --output text)

if [ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]; then
    echo "ERROR: Wrong AWS account."
    echo "Expected: $EXPECTED_ACCOUNT_ID"
    echo "Current:  $ACCOUNT_ID"
    exit 1
fi

echo "AWS account verified: $ACCOUNT_ID"
echo "Region: $REGION"
echo "Bucket: $BUCKET_NAME"
echo "Security group: $SG_NAME"
echo "IAM role: $ROLE_NAME"
echo "IAM policy: $POLICY_NAME"
echo "Instance profile: $INSTANCE_PROFILE"
echo "Dry run: $DRY_RUN"

POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"
SSM_POLICY_ARN="arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

# ==========================================
# Step 2 - Inspect lab resources
# ==========================================

echo ""
echo "Checking existing lab resources..."

# Check S3 bucket and its objects.

BUCKET_EXISTS=false

if aws s3api head-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" >/dev/null 2>&1; then

    BUCKET_EXISTS=true
    echo ""
    echo "S3 bucket found: $BUCKET_NAME"

    aws s3 ls "s3://$BUCKET_NAME/" \
        --recursive \
        --region "$REGION"
else
    echo "S3 bucket not found or access denied."
fi

# Check security group in the expected VPC.

SG_ID=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters \
      "Name=group-name,Values=$SG_NAME" \
      "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[0].GroupId" \
    --output text)

echo ""
echo "Security group: $SG_ID"

# Check IAM role.

ROLE_EXISTS=false

if aws iam get-role \
    --role-name "$ROLE_NAME" \
    >/dev/null 2>&1; then

    ROLE_EXISTS=true
    echo "IAM role found: $ROLE_NAME"
else
    echo "IAM role not found or access denied."
fi

# Check custom IAM policy.

POLICY_EXISTS=false

if aws iam get-policy \
    --policy-arn "$POLICY_ARN" \
    >/dev/null 2>&1; then

    POLICY_EXISTS=true
    echo "IAM policy found: $POLICY_NAME"
else
    echo "IAM policy not found or access denied."
fi

# Check instance profile.

PROFILE_EXISTS=false

if aws iam get-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE" \
    >/dev/null 2>&1; then

    PROFILE_EXISTS=true
    echo "Instance profile found: $INSTANCE_PROFILE"
else
    echo "Instance profile not found or access denied."
fi

# Find active instances using the lab instance profile.

echo ""
echo "Checking EC2 instances..."

INSTANCE_IDS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters \
      "Name=iam-instance-profile.arn,Values=arn:aws:iam::$ACCOUNT_ID:instance-profile/$INSTANCE_PROFILE" \
      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
    echo "Instances using lab profile: $INSTANCE_IDS"
else
    echo "No active instances using the lab profile."
fi

# ==========================================
# Step 3 - Preview and safety confirmation
# ==========================================

echo ""
echo "=================================="
echo "Cleanup summary"
echo "=================================="

echo "Bucket exists: $BUCKET_EXISTS"
echo "Security group: $SG_ID"
echo "Role exists: $ROLE_EXISTS"
echo "Policy exists: $POLICY_EXISTS"
echo "Profile exists: $PROFILE_EXISTS"
echo "EC2 instances: ${INSTANCE_IDS:-None}"

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "DRY RUN: No resources have been deleted."
    echo "Review the resources before enabling cleanup."
    exit 0
fi

# Refuse to delete a security group with an
# unexpected identifier.

if [ "$SG_ID" != "None" ] && \
   [ -n "$SG_ID" ] && \
   [ "$SG_ID" != "$EXPECTED_SG_ID" ]; then

    echo "ERROR: Security group ID does not match."
    echo "Expected: $EXPECTED_SG_ID"
    echo "Found:    $SG_ID"
    echo "Cleanup cancelled."
    exit 1
fi

echo ""
echo "WARNING: This will permanently delete lab resources."
echo "S3 objects and EC2 instances cannot be recovered"
echo "through this script."

read -r -p "Type DELETE to continue: " CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

# ==========================================
# Step 4 - Terminate lab EC2 instances
# ==========================================

if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then

    echo ""
    echo "Terminating EC2 instances: $INSTANCE_IDS"

    read -r -a INSTANCE_ARRAY <<< "$INSTANCE_IDS"

    aws ec2 terminate-instances \
        --instance-ids "${INSTANCE_ARRAY[@]}" \
        --region "$REGION"

    aws ec2 wait instance-terminated \
        --instance-ids "${INSTANCE_ARRAY[@]}" \
        --region "$REGION"

    echo "EC2 instances terminated."
else
    echo "No EC2 instances to terminate."
fi

# ==========================================
# Step 5 - Remove instance profile
# ==========================================

if [ "$PROFILE_EXISTS" = true ]; then

    echo ""
    echo "Removing instance profile..."

    PROFILE_ROLES=$(aws iam get-instance-profile \
        --instance-profile-name "$INSTANCE_PROFILE" \
        --query "InstanceProfile.Roles[].RoleName" \
        --output text)

    if [ -n "$PROFILE_ROLES" ] && \
       [ "$PROFILE_ROLES" != "None" ]; then

        if [ "$PROFILE_ROLES" != "$ROLE_NAME" ]; then
            echo "ERROR: Unexpected role in instance profile."
            exit 1
        fi

        aws iam remove-role-from-instance-profile \
            --instance-profile-name "$INSTANCE_PROFILE" \
            --role-name "$ROLE_NAME"
    fi

    aws iam delete-instance-profile \
        --instance-profile-name "$INSTANCE_PROFILE"

    echo "Instance profile deleted."
fi

# ==========================================
# Step 6 - Detach IAM policies and delete role
# ==========================================

if [ "$ROLE_EXISTS" = true ]; then

    echo ""
    echo "Removing IAM role..."

    # Verify that no unexpected managed policies
    # are attached before deleting the role.

    ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
        --role-name "$ROLE_NAME" \
        --query "AttachedPolicies[].PolicyArn" \
        --output text)

    for ATTACHED_ARN in $ATTACHED_POLICIES; do
        if [ "$ATTACHED_ARN" != "$POLICY_ARN" ] && \
           [ "$ATTACHED_ARN" != "$SSM_POLICY_ARN" ]; then

            echo "ERROR: Unexpected attached policy:"
            echo "$ATTACHED_ARN"
            exit 1
        fi
    done

    # Do not remove roles with inline policies.

    INLINE_POLICIES=$(aws iam list-role-policies \
        --role-name "$ROLE_NAME" \
        --query "PolicyNames" \
        --output text)

    if [ -n "$INLINE_POLICIES" ] && \
       [ "$INLINE_POLICIES" != "None" ]; then

        echo "ERROR: Role has inline policies."
        echo "Cleanup cancelled to protect these policies."
        exit 1
    fi

    for ATTACHED_ARN in $ATTACHED_POLICIES; do
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "$ATTACHED_ARN"
    done

    aws iam delete-role \
        --role-name "$ROLE_NAME"

    echo "IAM role deleted."
fi

# ==========================================
# Step 7 - Delete custom IAM policy
# ==========================================

if [ "$POLICY_EXISTS" = true ]; then

    echo ""
    echo "Deleting custom IAM policy..."

    # Check that the policy is not attached elsewhere.

    ATTACHMENT_COUNT=$(aws iam get-policy \
        --policy-arn "$POLICY_ARN" \
        --query "Policy.AttachmentCount" \
        --output text)

    if [ "$ATTACHMENT_COUNT" != "0" ]; then
        echo "ERROR: Policy is still attached to resources."
        exit 1
    fi

    aws iam delete-policy \
        --policy-arn "$POLICY_ARN"

    echo "IAM policy deleted."
fi

# ==========================================
# Step 8 - Delete security group
# ==========================================

if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then

    echo ""
    echo "Deleting security group: $SG_ID"

    # AWS prevents deletion if the group is still
    # referenced by resources or other security groups.

    aws ec2 delete-security-group \
        --group-id "$SG_ID" \
        --region "$REGION"

    echo "Security group deleted."
fi

# ==========================================
# Step 9 - Empty and delete S3 bucket
# ==========================================

if [ "$BUCKET_EXISTS" = true ]; then

    echo ""
    echo "Preparing to delete S3 bucket..."

    # Check bucket versioning status.

    VERSIONING_STATUS=$(aws s3api get-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --query "Status" \
        --output text)

    if [ "$VERSIONING_STATUS" = "Enabled" ] || \
       [ "$VERSIONING_STATUS" = "Suspended" ]; then

        echo "ERROR: Bucket versioning is or was enabled."
        echo "Manual review of object versions is required."
        exit 1
    fi

    # Empty the lab bucket.

    aws s3 rm "s3://$BUCKET_NAME" \
        --recursive \
        --region "$REGION"

    # Delete the empty bucket.

    aws s3api delete-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION"

    echo "S3 bucket deleted."
fi

# ==========================================
# Step 10 - Cleanup completed
# ==========================================

echo ""
echo "=================================="
echo "Task 2.1 cleanup completed."
echo "=================================="
