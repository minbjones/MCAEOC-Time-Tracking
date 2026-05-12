import base64
import hashlib
import hmac

from config import settings


def is_valid_api_key(candidate: str) -> bool:
    return hmac.compare_digest(candidate or "", settings.mobile_api_key)


def decode_b64(value: str) -> bytes:
    return base64.b64decode(value.encode("utf-8"), validate=True)


def hash_password(salt: str, password: str) -> str:
    return hashlib.sha256(f"{salt}{password}".encode("utf-16le")).hexdigest().upper()
