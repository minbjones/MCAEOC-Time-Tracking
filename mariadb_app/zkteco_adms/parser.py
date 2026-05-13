from __future__ import annotations

from datetime import datetime
import re
from typing import Iterable


DATE_FORMATS = (
    "%Y-%m-%d %H:%M:%S",
    "%Y/%m/%d %H:%M:%S",
    "%m/%d/%Y %H:%M:%S",
    "%Y-%m-%d %H:%M",
    "%Y/%m/%d %H:%M",
    "%m/%d/%Y %H:%M",
    "%Y-%m-%dT%H:%M:%S",
    "%Y-%m-%dT%H:%M:%S.%f",
    "%Y-%m-%dT%H:%M:%S%z",
    "%Y-%m-%d",
)

USER_ID_KEYS = ("pin", "userid", "enrollnumber", "badgenumber", "personid")
USER_NAME_KEYS = ("name", "username", "personname")
TIMESTAMP_KEYS = ("datetime", "timestamp", "time", "checktime", "punchtime", "transactiontime")
DIRECTION_KEYS = ("status", "punchdirection", "direction", "state")
DEVICE_KEYS = ("sn", "serialnumber", "device", "deviceidentifier", "terminal", "devsn")


def parse_payload(query_params: dict[str, str], body_text: str) -> tuple[str | None, list[dict[str, str]]]:
    device_identifier = first_present(query_params, DEVICE_KEYS)
    records: list[dict[str, str]] = []
    normalized_body = body_text.replace("\r\n", "\n").strip()

    if normalized_body:
        records.extend(parse_body_lines(normalized_body.splitlines()))

    if not records:
        single_record = extract_record_from_mapping(query_params)
        if single_record:
            records.append(single_record)

    for record in records:
        if not record.get("device_identifier") and device_identifier:
            record["device_identifier"] = device_identifier

    if not device_identifier:
        device_identifier = first_present((record for record in records), ("device_identifier",))

    return device_identifier, records


def parse_body_lines(lines: Iterable[str]) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("OPLOG") or line.startswith("ATTLOG"):
            line = line.split(" ", 1)[1] if " " in line else ""
        if not line:
            continue

        kv_record = parse_key_value_line(line)
        if kv_record:
            records.append(kv_record)
            continue

        tab_record = parse_delimited_line(line, "\t")
        if tab_record:
            records.append(tab_record)
            continue

        comma_record = parse_delimited_line(line, ",")
        if comma_record:
            records.append(comma_record)

    return [record for record in records if extract_record_from_mapping(record)]


def parse_key_value_line(line: str) -> dict[str, str] | None:
    pairs = re.findall(r"([A-Za-z0-9_]+)=([^\t,;]+)", line)
    if not pairs:
        return None
    record = {key.strip().lower(): value.strip() for key, value in pairs}
    return extract_record_from_mapping(record)


def parse_delimited_line(line: str, delimiter: str) -> dict[str, str] | None:
    parts = [part.strip() for part in line.split(delimiter)]
    if len(parts) < 2:
        return None
    record = {
        "pin": parts[0],
        "datetime": parts[1],
    }
    if len(parts) >= 3:
        record["status"] = parts[2]
    if len(parts) >= 4:
        record["verifycode"] = parts[3]
    return extract_record_from_mapping(record)


def extract_record_from_mapping(source: dict[str, str]) -> dict[str, str] | None:
    external_user_id = first_present(source, USER_ID_KEYS)
    punch_timestamp = first_present(source, TIMESTAMP_KEYS)
    if not external_user_id or not punch_timestamp:
        return None
    record = {
        "external_user_id": external_user_id,
        "punch_timestamp": punch_timestamp,
    }
    external_user_name = first_present(source, USER_NAME_KEYS)
    if external_user_name:
        record["external_user_name"] = external_user_name
    punch_direction = first_present(source, DIRECTION_KEYS)
    if punch_direction:
        record["punch_direction"] = punch_direction
    device_identifier = first_present(source, DEVICE_KEYS)
    if device_identifier:
        record["device_identifier"] = device_identifier
    return record


def normalize_punch_timestamp(value: str) -> datetime:
    candidate = value.strip()
    for fmt in DATE_FORMATS:
        try:
            return datetime.strptime(candidate, fmt)
        except ValueError:
            continue
    raise ValueError(f"Unsupported punch timestamp format: {value}")


def first_present(source, keys: tuple[str, ...]) -> str | None:
    if isinstance(source, dict):
        for key in keys:
            value = source.get(key) or source.get(key.lower()) or source.get(key.upper())
            if value not in (None, ""):
                return str(value).strip()
        return None

    for item in source:
        for key in keys:
            value = item.get(key)
            if value not in (None, ""):
                return str(value).strip()
    return None
