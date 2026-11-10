
import boto3
import time

s3 = boto3.client("s3", region_name="eu-north-1")

bucket_name = "d7078e-lab2-python-se-20261109-ml"
file_name = "test_2mb.bin"
download_name = "downloaded_2mb.bin"

# Measure upload time
start = time.perf_counter()
s3.upload_file(file_name, bucket_name, file_name)
upload_time = time.perf_counter() - start

# Measure download time
start = time.perf_counter()
s3.download_file(bucket_name, file_name, download_name)
download_time = time.perf_counter() - start

print(f"Upload time: {upload_time:.4f} seconds")
print(f"Download time: {download_time:.4f} seconds")
