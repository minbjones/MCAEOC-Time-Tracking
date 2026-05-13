package com.example.employeetimetracking.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.height
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import com.example.employeetimetracking.R
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.example.employeetimetracking.data.EmployeeListItem

private val DeepBlue = Color(0xFF0B3D91)
private val MidnightBlue = Color(0xFF072A63)
private val SkyBlue = Color(0xFF4F8FE8)
private val PanelBlue = Color(0x332A5CAA)

@Composable
fun EmployeeTimeTrackingApp(viewModel: MainViewModel) {
    val sessionState by viewModel.sessionState.collectAsState()
    EmployeeTimeTrackingContent(
        sessionState = sessionState,
        onRefreshEmployees = viewModel::loadEmployees,
        onSelectEnrollmentEmployee = viewModel::selectEmployee,
        onCaptureClockEvent = viewModel::identifyAndClock,
        onEnrollmentCapture = viewModel::enrollFace
    )
}

@Composable
private fun EmployeeTimeTrackingContent(
    sessionState: SessionState,
    onRefreshEmployees: () -> Unit,
    onSelectEnrollmentEmployee: (EmployeeListItem) -> Unit,
    onCaptureClockEvent: (ByteArray) -> Unit,
    onEnrollmentCapture: (ByteArray, () -> Unit) -> Unit
) {
    val appColors = ButtonDefaults.buttonColors(
        containerColor = MidnightBlue,
        contentColor = Color.White
    )

    MaterialTheme {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(SkyBlue, DeepBlue, MidnightBlue)
                    )
                )
        ) {
            Scaffold(containerColor = Color.Transparent) { padding ->
                KioskCameraScreen(
                    padding = padding,
                    sessionState = sessionState,
                    buttonColors = appColors,
                    onRefreshEmployees = onRefreshEmployees,
                    onSelectEnrollmentEmployee = onSelectEnrollmentEmployee,
                    onCaptureClockEvent = onCaptureClockEvent,
                    onEnrollmentCapture = onEnrollmentCapture
                )
            }

            val greeting = sessionState.greetingMessage
            if (greeting != null) {
                GreetingOverlay(message = greeting)
            }
        }
    }
}

@Composable
private fun GreetingOverlay(message: String) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xCC041833)),
        contentAlignment = Alignment.Center
    ) {
        Card(colors = CardDefaults.cardColors(containerColor = MidnightBlue)) {
            Column(
                modifier = Modifier.padding(28.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(message, style = MaterialTheme.typography.headlineSmall, color = Color.White)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun KioskCameraScreen(
    padding: PaddingValues,
    sessionState: SessionState,
    buttonColors: androidx.compose.material3.ButtonColors,
    onRefreshEmployees: () -> Unit,
    onSelectEnrollmentEmployee: (EmployeeListItem) -> Unit,
    onCaptureClockEvent: (ByteArray) -> Unit,
    onEnrollmentCapture: (ByteArray, () -> Unit) -> Unit
) {
    var showEnrollmentDialog by rememberSaveable { mutableStateOf(false) }
    var showEnrollmentAccessDialog by rememberSaveable { mutableStateOf(false) }
    var adminCode by rememberSaveable { mutableStateOf("") }
    var employeeMenuExpanded by rememberSaveable { mutableStateOf(false) }
    var employeeSearchQuery by rememberSaveable { mutableStateOf("") }
    val enrollmentUnlocked = adminCode == "1400"

    LaunchedEffect(showEnrollmentDialog) {
        if (showEnrollmentDialog) {
            employeeSearchQuery = sessionState.enrollmentEmployeeName
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(20.dp)
                .verticalScroll(rememberScrollState())
        ) {
            Card(colors = CardDefaults.cardColors(containerColor = PanelBlue)) {
                Row(
                    modifier = Modifier.padding(20.dp),
                    horizontalArrangement = Arrangement.spacedBy(20.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1.45f)
                            .fillMaxHeight()
                    ) {
                        if (!showEnrollmentDialog) {
                            CameraCaptureCard(
                                title = "",
                                captureButtonLabel = "Capture Now",
                                helperText = if (sessionState.employees.any { it.has_face_template }) {
                                    "Hands-free capture is active for enrolled employees and scans about every 2 seconds."
                                } else {
                                    "Enroll at least one employee to enable hands-free capture."
                                },
                                buttonColors = buttonColors,
                                previewHeight = 420.dp,
                                enabled = !sessionState.isLoading,
                                autoCaptureEnabled = sessionState.employees.any { it.has_face_template } && !showEnrollmentDialog,
                                autoCaptureBlockedUntilMillis = sessionState.autoCaptureCooldownUntilMillis,
                                onImageCaptured = onCaptureClockEvent
                            )
                        } else {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(420.dp)
                                    .background(Color.Black.copy(alpha = 0.2f)),
                                contentAlignment = Alignment.Center
                            ) {
                                Text("Main camera paused during enrollment", color = Color.White)
                            }
                        }
                    }

                    Column(
                        modifier = Modifier
                            .weight(0.9f)
                            .fillMaxHeight(),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Image(
                            painter = painterResource(id = R.drawable.cap_huggy),
                            contentDescription = "MCAEOC Logo",
                            modifier = Modifier.size(180.dp)
                        )
                        Spacer(modifier = Modifier.height(18.dp))
                        Text(
                            "Welcome to MCAEOC",
                            style = MaterialTheme.typography.headlineSmall,
                            color = Color.White
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        Button(
                            onClick = {
                                adminCode = ""
                                showEnrollmentAccessDialog = true
                            },
                            modifier = Modifier.width(220.dp),
                            colors = buttonColors
                        ) {
                            Text("Enrollment")
                        }
                    }
                }
            }
        }

    }

    if (showEnrollmentAccessDialog) {
        AlertDialog(
            onDismissRequest = { showEnrollmentAccessDialog = false },
            containerColor = MidnightBlue,
            title = { Text("Enrollment Access", color = Color.White) },
            text = {
                OutlinedTextField(
                    value = adminCode,
                    onValueChange = { adminCode = it.filter(Char::isDigit).take(4) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Code") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White,
                        focusedLabelColor = Color.White,
                        unfocusedLabelColor = Color.White,
                        focusedBorderColor = Color.White,
                        unfocusedBorderColor = Color.White.copy(alpha = 0.7f),
                        cursorColor = Color.White
                    )
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        if (enrollmentUnlocked) {
                            onRefreshEmployees()
                            showEnrollmentAccessDialog = false
                            showEnrollmentDialog = true
                        }
                    },
                    enabled = enrollmentUnlocked,
                    colors = buttonColors
                ) {
                    Text("Open")
                }
            },
            dismissButton = {
                Button(
                    onClick = { showEnrollmentAccessDialog = false },
                    colors = buttonColors
                ) {
                    Text("Cancel")
                }
            }
        )
    }

    if (showEnrollmentDialog) {
        AlertDialog(
            onDismissRequest = { showEnrollmentDialog = false },
            containerColor = MidnightBlue,
            title = { Text("Enrollment", color = Color.White) },
            text = {
                Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    Box(modifier = Modifier.weight(1.2f)) {
                        CameraCaptureCard(
                            title = "",
                            captureButtonLabel = "Capture and Enroll",
                            helperText = "",
                            buttonColors = buttonColors,
                            previewHeight = 320.dp,
                            enabled = sessionState.enrollmentEmployeeId != null,
                            onImageCaptured = {
                                onEnrollmentCapture(it) {
                                    showEnrollmentDialog = false
                                }
                            }
                        )
                    }

                    Column(
                        modifier = Modifier.weight(0.9f),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        if (sessionState.employees.isEmpty()) {
                            Text("No employees loaded. Check connection or status: ${sessionState.statusMessage}", color = Color.Red)
                        }

                        val filteredEmployees = sessionState.employees.filter {
                            it.full_name.contains(employeeSearchQuery, ignoreCase = true) ||
                                    it.employee_id.toString().contains(employeeSearchQuery)
                        }

                        ExposedDropdownMenuBox(
                            expanded = employeeMenuExpanded,
                            onExpandedChange = { employeeMenuExpanded = !employeeMenuExpanded }
                        ) {
                            OutlinedTextField(
                                value = employeeSearchQuery,
                                onValueChange = {
                                    employeeSearchQuery = it
                                    employeeMenuExpanded = true
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .menuAnchor(MenuAnchorType.PrimaryEditable),
                                label = { Text("Employee") },
                                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = employeeMenuExpanded) },
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                                colors = OutlinedTextFieldDefaults.colors(
                                    focusedTextColor = Color.White,
                                    unfocusedTextColor = Color.White,
                                    focusedLabelColor = Color.White,
                                    unfocusedLabelColor = Color.White,
                                    focusedBorderColor = Color.White,
                                    unfocusedBorderColor = Color.White.copy(alpha = 0.7f),
                                    cursorColor = Color.White
                                )
                            )
                            if (filteredEmployees.isNotEmpty()) {
                                ExposedDropdownMenu(
                                    expanded = employeeMenuExpanded,
                                    onDismissRequest = { employeeMenuExpanded = false },
                                    containerColor = MidnightBlue
                                ) {
                                    filteredEmployees.forEach { employee ->
                                        DropdownMenuItem(
                                            text = {
                                                Text(
                                                    "${employee.full_name} (${employee.employee_id})",
                                                    color = Color.White
                                                )
                                            },
                                            onClick = {
                                                onSelectEnrollmentEmployee(employee)
                                                employeeSearchQuery = employee.full_name
                                                employeeMenuExpanded = false
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        if (sessionState.enrollmentEmployeeId != null) {
                            Text(
                                "Ready to enroll face data for ${sessionState.enrollmentEmployeeName}.",
                                color = Color.White
                            )
                        } else {
                            Text(
                                "Select an employee to prepare face enrollment.",
                                color = Color.White
                            )
                        }
                        Text(
                            "Status: ${sessionState.statusMessage}",
                            color = Color.White
                        )
                    }
                }
            },
            confirmButton = {
                Button(
                    onClick = { showEnrollmentDialog = false },
                    modifier = Modifier.width(160.dp),
                    colors = buttonColors
                ) {
                    Text("Close")
                }
            }
        )
    }
}

@Preview(showBackground = true, widthDp = 1024, heightDp = 600)
@Composable
fun EmployeeTimeTrackingAppPreview() {
    val sampleEmployees = listOf(
        EmployeeListItem(1, "John Doe", "Staff", true),
        EmployeeListItem(2, "Jane Smith", "Manager", false)
    )
    val sampleState = SessionState(
        employees = sampleEmployees,
        statusMessage = "Kiosk Ready"
    )
    EmployeeTimeTrackingContent(
        sessionState = sampleState,
        onRefreshEmployees = {},
        onSelectEnrollmentEmployee = {},
        onCaptureClockEvent = {},
        onEnrollmentCapture = { _, _ -> }
    )
}
