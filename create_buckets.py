
import boto3
from botocore.exceptions import ClientError

# Bucket names and AWS regions
buckets = {
    "eu-north-1": "d7078e-lab2-python-se-20261109-ml",
    "eu-central-1": "d7078e-lab2-python-de-20261109-ml",
     "eu-west-3": "d7078e-lab2-python-fr-20261109-ml"
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
