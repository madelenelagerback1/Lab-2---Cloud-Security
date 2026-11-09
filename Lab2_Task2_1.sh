
#!/bin/bash
set -e
cd "$(dirname "$0")"

# Task 2.1 - AWS CLI Bash Script
# Cloud Security D7078E

# Configuration variables
REGION="eu-north-1"
INSTANCE_TYPE="t3.micro"
VPC_ID="vpc-0e773d5d243e2af90"
BUCKET_NAME="d7078e-lab2-storage-20261109-ml"
MY_IP="95.61.57.38/32"

SG_NAME="Lab2-SecurityGroup"
ROLE_NAME="Lab2EC2Role"
POLICY_NAME="Lab2S3Policy"
INSTANCE_PROFILE="Lab2EC2Profile"

# JSON policy files
S3_POLICY_FILE="Labs3Policy.json"
TRUST_POLICY_FILE="Lab2TrustPolicy.json"



# Step (a) - Create a security group

SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Security group for Lab 2" \
    --vpc-id "$VPC_ID" \
    --region "$REGION" \
    --query "GroupId" \
    --output text)

echo "Security group created: $SG_ID"


# Step (b) - Add an inbound SSH rule
# Allow SSH access on TCP port 22 from my IP address only.

aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr "$MY_IP" \
    --region "$REGION"

echo "SSH rule added for IP: $MY_IP"

# Step (c) - Verify the SSH security group rule

aws ec2 describe-security-groups \
    --group-ids "$SG_ID" \
    --region "$REGION" \
    --query "SecurityGroups[0].IpPermissions" \
    --output json

echo "SSH rule verified."


# Step (d) - Add an inbound HTTP rule
# Allow HTTP traffic on TCP port 80 from anywhere.

aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr "0.0.0.0/0" \
    --region "$REGION"

# Verify the security group inbound rules.

aws ec2 describe-security-groups \
    --group-ids "$SG_ID" \
    --region "$REGION" \
    --query "SecurityGroups[0].IpPermissions" \
    --output json

echo "HTTP rule added and security group rules verified."


# Step (e) - Create an S3 bucket
# Create the bucket in the Stockholm AWS Region.

aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"

echo "S3 bucket created: $BUCKET_NAME"

# Verify that the bucket exists.

aws s3api head-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION"

echo "S3 bucket verified."


# Step (f) - Create a custom IAM policy
# Grant permissions to list the S3 bucket and manage its objects.

POLICY_ARN=$(aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "file://$S3_POLICY_FILE" \
    --query "Policy.Arn" \
    --output text)

echo "IAM policy created: $POLICY_ARN"

# Verify the IAM policy.

aws iam get-policy \
    --policy-arn "$POLICY_ARN"


# Step (g) - Create an IAM role for EC2
# Use the trust policy to allow EC2 to assume the role.

aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://$TRUST_POLICY_FILE"

echo "IAM role created: $ROLE_NAME"

# Verify that the IAM role exists.

aws iam get-role \
    --role-name "$ROLE_NAME"


# Step (h) - Attach the custom IAM policy to the EC2 role
# Grant the role permissions to access the lab S3 bucket.

aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN"

echo "IAM policy attached to role: $ROLE_NAME"

# Verify that the policy is attached to the role.

aws iam list-attached-role-policies \
    --role-name "$ROLE_NAME"

echo "IAM role policy attachment verified."


# Step (i) - Launch an EC2 instance
# Create an instance profile and associate the IAM role.

aws iam create-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE"

aws iam add-role-to-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE" \
    --role-name "$ROLE_NAME"

# Allow the EC2 instance to connect through AWS Systems Manager.

aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

# Wait for IAM changes to propagate.
echo "Waiting for IAM configuration..."
sleep 30

# Find the latest Amazon Linux 2023 AMI in Stockholm.

AMI_ID=$(aws ssm get-parameter \
    --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
    --region "$REGION" \
    --query "Parameter.Value" \
    --output text)

# Launch the EC2 instance with the security group and IAM instance profile.

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --security-group-ids "$SG_ID" \
    --iam-instance-profile "Name=$INSTANCE_PROFILE" \
    --region "$REGION" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Lab2-EC2}]' \
    --query "Instances[0].InstanceId" \
    --output text)

echo "EC2 instance launched: $INSTANCE_ID"

# Wait until the instance is running.

aws ec2 wait instance-running \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION"

# Verify the EC2 instance configuration.

aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Reservations[0].Instances[0].[InstanceId,State.Name,IamInstanceProfile.Arn]" \
    --output table

echo "Task 2.1 steps (a)-(i) completed."
