
import boto3

s3 = boto3.client("s3", region_name="eu-north-1")

bucket_name = "d7078e-lab2-python-se-20261109-ml"
object_name = "test_upload.txt"

s3.delete_object(Bucket=bucket_name, Key=object_name)

print("Object deleted successfully!")
print("Bucket:", bucket_name)
print("Deleted object:", object_name)
