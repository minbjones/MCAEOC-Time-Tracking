import os


class Settings:
    api_title = "Employee Time Tracking Mobile API"
    sql_connection_string = os.getenv(
        "EMPLOYEE_TIME_TRACKING_CONNECTION_STRING",
        "DRIVER={ODBC Driver 17 for SQL Server};"
        "SERVER=BLANTON-I9\\SQLEXPRESS;"
        "DATABASE=EmployeeTimeTracking;"
        "Trusted_Connection=yes;",
    )
    mobile_api_key = os.getenv("EMPLOYEE_TIME_TRACKING_MOBILE_API_KEY", "change-me")
    liveness_threshold = float(os.getenv("FACE_LIVENESS_THRESHOLD", "0.80"))
    face_model_name = os.getenv("FACE_MODEL_NAME", "ArcFace")
    face_detector_backend = os.getenv("FACE_DETECTOR_BACKEND", "ssd")
    face_distance_threshold = float(os.getenv("FACE_DISTANCE_THRESHOLD", "0.30"))
    face_align = os.getenv("FACE_ALIGN", "true").strip().lower() in {"1", "true", "yes", "on"}
    face_enforce_detection = os.getenv("FACE_ENFORCE_DETECTION", "true").strip().lower() in {"1", "true", "yes", "on"}
    face_expand_percentage = int(os.getenv("FACE_EXPAND_PERCENTAGE", "10"))
    face_max_image_size = int(os.getenv("FACE_MAX_IMAGE_SIZE", "1280"))


settings = Settings()
