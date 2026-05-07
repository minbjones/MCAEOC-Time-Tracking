from typing import Optional

from pydantic import BaseModel, Field


class LoginRequest(BaseModel):
    email: str
    password: str
    device_identifier: str
    device_name: Optional[str] = None


class DeviceRegistrationRequest(BaseModel):
    employee_id: int
    device_identifier: str
    device_name: Optional[str] = None
    platform: str = "Android"


class FaceEnrollmentRequest(BaseModel):
    employee_id: int
    template_version: str = "v1"
    face_template_b64: str
    notes: Optional[str] = None


class FaceClockRequest(BaseModel):
    employee_id: int
    device_identifier: str
    event_type: str = Field(pattern="^(ClockIn|ClockOut)$")
    selfie_image_b64: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None


class IdentifyClockRequest(BaseModel):
    device_identifier: str
    selfie_image_b64: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None


class ApiResponse(BaseModel):
    success: bool
    message: str


class EmployeeListItem(BaseModel):
    employee_id: int
    full_name: str
    role_name: str
    has_face_template: bool


class LoginResponse(ApiResponse):
    employee_id: int
    full_name: str
    role_name: str
    has_face_template: bool


class FaceClockResponse(ApiResponse):
    employee_id: Optional[int] = None
    full_name: Optional[str] = None
    event_type: Optional[str] = None
    verification_status: str
    confidence_score: float
    liveness_score: float
