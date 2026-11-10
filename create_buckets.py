
import boto3
from botocore.exceptions import ClientError

# Get the AWS account ID automatically
sts = boto3.client("sts")
account_id = sts.get_caller_identity()["Account"]

# Bucket names and AWS regions
buckets = {
    "eu-north-1": f"d7078e-lab2-python-se-{account_id}",
    "eu-central-1": f"d7078e-lab2-python-de-{account_id}",
    "eu-west-3": f"d7078e-lab2-python-fr-{account_id}"
}

for region, bucket_name in buckets.items():
    print(f"\nCreating bucket: {bucket_name}")
    print(f"Region: {region}")

    s3 = boto3.client("s3", region_name=region)

    try:
        s3.create_bucket(
            Bucket=bucket_name,
            CreateBucketConfiguration={
                "LocationConstraint": region
            }
        )

        print("Bucket created successfully!")

    except ClientError as error:
        print("Error:", error.response["Error"]["Code"])
        print(error.response["Error"]["Message"])
