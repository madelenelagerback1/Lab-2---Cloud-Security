import boto3

# Create an S3 client in the Stockholm region
s3 = boto3.client("s3", region_name="eu-north-1")

print("S3 client created successfully!")
print("AWS Region:", s3.meta.region_name)