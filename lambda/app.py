\
import base64
import json
import os
import time
from urllib.parse import unquote

import boto3

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET"]
PREFIX = os.environ.get("PREFIX", "site").strip("/")


def response(status, body, content_type="text/html; charset=utf-8", headers=None, is_base64=False):
    result_headers = {"Content-Type": content_type}
    if headers:
        result_headers.update(headers)
    return {
        "statusCode": status,
        "headers": result_headers,
        "isBase64Encoded": is_base64,
        "body": body,
    }


def handler(event, context):
    started = time.perf_counter()
    path = unquote((event.get("rawPath") or "/").split("?", 1)[0])
    if path == "/":
        path = "/index.html"

    try:
        if path not in ("/index.html", "/style.css", "/cv.pdf"):
            result = response(404, "<!doctype html><html><body><h1>404 Not Found</h1></body></html>")
        else:
            key = f"{PREFIX}/{path.lstrip('/')}"
            obj = s3.get_object(Bucket=BUCKET, Key=key)
            data = obj["Body"].read()

            if path == "/index.html":
                instance_or_function = getattr(context, "function_name", "cv-func-23l-3000")
                html = data.decode("utf-8").replace("{{HOSTED_ON}}", f"Lambda {instance_or_function}")
                result = response(
                    200, html, "text/html; charset=utf-8",
                    {"Cache-Control": "max-age=60"}
                )
            elif path == "/style.css":
                result = response(200, data.decode("utf-8"), "text/css; charset=utf-8")
            else:
                result = response(
                    200, base64.b64encode(data).decode("ascii"),
                    "application/pdf", is_base64=True
                )
    except Exception:
        # Avoid returning internal AWS details to public callers; details remain in CloudWatch logs.
        result = response(500, "<!doctype html><html><body><h1>Internal Server Error</h1></body></html>")

    elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
    print(json.dumps({
        "fn": getattr(context, "function_name", "unknown"),
        "path": path,
        "status": result["statusCode"],
        "ms": elapsed_ms,
    }))
    return result
