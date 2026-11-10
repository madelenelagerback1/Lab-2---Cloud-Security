
import boto3

s3 = boto3.client("s3", region_name="eu-north-1")

bucket_name = "d7078e-lab2-python-se-20261109-ml"
file_name = "test_upload.txt"

s3.upload_file(file_name, bucket_name, file_name)

print("File uploaded successfully!")
print("Bucket:", bucket_name)
print("Object:", file_name)
