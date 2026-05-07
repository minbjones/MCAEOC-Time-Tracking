import base64
import hashlib

from config import settings


def hash_password(salt: str, password: str) -> str:
    return hashlib.sha256(f"{salt}{password}".encode("utf-16le")).hexdigest().upper()


def decode_b64(value: str) -> bytes:
    return base64.b64decode(value.encode("utf-8"))


def is_valid_api_key(api_key: str) -> bool:
    return api_key == settings.mobile_api_key
