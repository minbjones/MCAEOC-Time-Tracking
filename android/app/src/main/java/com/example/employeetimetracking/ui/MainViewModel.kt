package com.example.employeetimetracking.ui

import android.util.Base64
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.employeetimetracking.data.ApiClient
import com.example.employeetimetracking.data.EmployeeListItem
import com.example.employeetimetracking.data.FaceEnrollmentRequest
import com.example.employeetimetracking.data.IdentifyClockRequest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import retrofit2.HttpException

data class SessionState(
    val employees: List<EmployeeListItem> = emptyList(),
    val statusMessage: String = "Loading employees...",
    val isLoading: Boolean = false,
    val enrollmentEmployeeId: Int? = null,
    val enrollmentEmployeeName: String = "",
    val enrollmentHasFaceTemplate: Boolean = false,
    val greetingMessage: String? = null,
    val autoCaptureCooldownUntilMillis: Long = 0L
)

class MainViewModel : ViewModel() {
    private val _sessionState = MutableStateFlow(SessionState())
    val sessionState: StateFlow<SessionState> = _sessionState

    val deviceIdentifier = "android-emulator"

    init {
        loadEmployees()
    }

    fun loadEmployees() {
        viewModelScope.launch {
            _sessionState.value = _sessionState.value.copy(isLoading = true, statusMessage = "Loading employees...")
            runCatching {
                ApiClient.service.employees()
            }.onSuccess { employees ->
                _sessionState.value = _sessionState.value.copy(
                    employees = employees,
                    statusMessage = if (employees.isNotEmpty()) "Camera ready." else "No active employees found.",
                    isLoading = false
                )
            }.onFailure { error ->
                _sessionState.value = _sessionState.value.copy(
                    isLoading = false,
                    statusMessage = error.message ?: "Employee load failed."
                )
            }
        }
    }

    fun selectEmployee(employee: EmployeeListItem) {
        _sessionState.value = _sessionState.value.copy(
            enrollmentEmployeeId = employee.employee_id,
            enrollmentEmployeeName = employee.full_name,
            enrollmentHasFaceTemplate = employee.has_face_template,
            statusMessage = "Ready to enroll ${employee.full_name}."
        )
    }

    private fun extractErrorMessage(error: Throwable, fallback: String): String {
        return when (error) {
            is HttpException -> {
                val body = error.response()?.errorBody()?.string()
                if (!body.isNullOrBlank()) body else (error.message ?: fallback)
            }
            else -> error.message ?: fallback
        }
    }

    fun enrollFace(imageBytes: ByteArray, onSuccess: () -> Unit = {}) {
        val employeeId = _sessionState.value.enrollmentEmployeeId ?: return
        val employeeName = _sessionState.value.enrollmentEmployeeName
        viewModelScope.launch {
            _sessionState.value = _sessionState.value.copy(isLoading = true, statusMessage = "Enrolling face...")
            val encodedTemplate = Base64.encodeToString(imageBytes, Base64.NO_WRAP)
            runCatching {
                ApiClient.service.enrollFace(
                    FaceEnrollmentRequest(
                        employee_id = employeeId,
                        face_template_b64 = encodedTemplate,
                        notes = "Android scaffold enrollment"
                    )
                )
            }.onSuccess { response ->
                _sessionState.value = _sessionState.value.copy(
                    enrollmentHasFaceTemplate = true,
                    statusMessage = "$employeeName enrollment complete.",
                    isLoading = false
                )
                loadEmployees()
                onSuccess()
            }.onFailure { error ->
                _sessionState.value = _sessionState.value.copy(
                    isLoading = false,
                    statusMessage = extractErrorMessage(error, "Enrollment failed.")
                )
            }
        }
    }

    fun identifyAndClock(imageBytes: ByteArray) {
        viewModelScope.launch {
            _sessionState.value = _sessionState.value.copy(isLoading = true, statusMessage = "Checking face...")
            val encodedSelfie = Base64.encodeToString(imageBytes, Base64.NO_WRAP)
            runCatching {
                ApiClient.service.identifyAndClock(
                    IdentifyClockRequest(
                        device_identifier = deviceIdentifier,
                        selfie_image_b64 = encodedSelfie
                    )
                )
            }.onSuccess { response ->
                val cooldownUntil = System.currentTimeMillis() + if (response.success) 12_000L else 4_000L
                _sessionState.value = _sessionState.value.copy(
                    statusMessage = response.message,
                    greetingMessage = if (response.success && response.full_name != null && response.event_type != null) {
                        "Hello ${response.full_name}\n${response.event_type.replace("Clock", "Clock ")} successful"
                    } else {
                        null
                    },
                    isLoading = false,
                    autoCaptureCooldownUntilMillis = cooldownUntil
                )
                if (response.success) {
                    delay(3000)
                    _sessionState.value = _sessionState.value.copy(greetingMessage = null)
                }
            }.onFailure { error ->
                _sessionState.value = _sessionState.value.copy(
                    isLoading = false,
                    statusMessage = extractErrorMessage(error, "Face clocking failed."),
                    autoCaptureCooldownUntilMillis = System.currentTimeMillis() + 4_000L
                )
            }
        }
    }
}
