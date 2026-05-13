import os


class Settings:
    api_title = "MCAEOC ZKTeco ADMS Receiver"
    mariadb_connection_string = os.getenv(
        "EMPLOYEE_TIME_TRACKING_CONNECTION_STRING",
        "SERVER=mariadb;DATABASE=dbo;UID=mcaeoc;PWD=mcaeocpass-change-me;PORT=3306;",
    )
    system_name = os.getenv("ZKTECO_ADMS_SYSTEM_NAME", "ZKTecoIFace702")
    device_identifier_fallback = os.getenv("ZKTECO_ADMS_DEVICE_IDENTIFIER", "iface702")
    save_raw_payloads = os.getenv("ZKTECO_ADMS_SAVE_RAW_PAYLOADS", "true").strip().lower() in {"1", "true", "yes", "on"}
    raw_payload_max_length = int(os.getenv("ZKTECO_ADMS_RAW_PAYLOAD_MAX_LENGTH", "20000"))


settings = Settings()
