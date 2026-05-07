package com.example.employeetimetracking.data

data class LoginRequest(
    val email: String,
    val password: String,
    val device_identifier: String,
    val device_name: String?
)

data class LoginResponse(
    val success: Boolean,
    val message: String,
    val employee_id: Int,
    val full_name: String,
    val role_name: String,
    val has_face_template: Boolean
)

data class EmployeeListItem(
    val employee_id: Int,
    val full_name: String,
    val role_name: String,
    val has_face_template: Boolean
)

data class FaceEnrollmentRequest(
    val employee_id: Int,
    val template_version: String = "android-v1",
    val face_template_b64: String,
    val notes: String?
)

data class FaceClockRequest(
    val employee_id: Int,
    val device_identifier: String,
    val event_type: String,
    val selfie_image_b64: String,
    val latitude: Double? = null,
    val longitude: Double? = null
)

data class IdentifyClockRequest(
    val device_identifier: String,
    val selfie_image_b64: String,
    val latitude: Double? = null,
    val longitude: Double? = null
)

data class ApiMessageResponse(
    val success: Boolean,
    val message: String
)

data class FaceClockResponse(
    val success: Boolean,
    val message: String,
    val employee_id: Int?,
    val full_name: String?,
    val event_type: String?,
    val verification_status: String,
    val confidence_score: Double,
    val liveness_score: Double
)
