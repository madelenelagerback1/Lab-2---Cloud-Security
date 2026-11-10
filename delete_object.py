
import boto3

# Get the AWS account ID automatically
sts = boto3.client("sts")
account_id = sts.get_caller_identity()["Account"]

# Create S3 client in Stockholm
s3 = boto3.client("s3", region_name="eu-north-1")

# Bucket name based on AWS account ID
bucket_name = f"d7078e-lab2-python-se-{account_id}"
object_name = "test_upload.txt"

# Delete object from S3
s3.delete_object(Bucket=bucket_name, Key=object_name)

print("Object deleted successfully!")
print("Bucket:", bucket_name)
print("Deleted object:", object_name)
