package com.example.employeetimetracking.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import java.io.File

@Composable
fun CameraCaptureCard(
    title: String,
    captureButtonLabel: String,
    helperText: String,
    buttonColors: ButtonColors,
    previewHeight: androidx.compose.ui.unit.Dp = 280.dp,
    enabled: Boolean = true,
    autoCaptureEnabled: Boolean = false,
    autoCaptureIntervalMs: Long = 2_000L,
    autoCaptureBlockedUntilMillis: Long = 0L,
    onImageCaptured: (ByteArray) -> Unit
) {
    val context = LocalContext.current
    val inspectionMode = LocalInspectionMode.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val controller = remember {
        if (inspectionMode) null else {
            LifecycleCameraController(context).apply {
                cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA
                setEnabledUseCases(LifecycleCameraController.IMAGE_CAPTURE)
            }
        }
    }
    var hasPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        )
    }
    var nextAutoCaptureAtMillis by remember { mutableStateOf(0L) }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasPermission = granted
    }

    LaunchedEffect(Unit) {
        if (!hasPermission) {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    LaunchedEffect(autoCaptureEnabled, enabled, hasPermission, controller, autoCaptureBlockedUntilMillis) {
        if (!autoCaptureEnabled || !enabled || !hasPermission || controller == null) {
            return@LaunchedEffect
        }

        while (isActive) {
            val now = System.currentTimeMillis()
            val nextAllowedCapture = maxOf(nextAutoCaptureAtMillis, autoCaptureBlockedUntilMillis)
            if (now >= nextAllowedCapture) {
                nextAutoCaptureAtMillis = now + autoCaptureIntervalMs
                captureToBytes(context, controller, onImageCaptured)
            }
            delay(500L)
        }
    }

    DisposableEffect(lifecycleOwner, hasPermission, controller) {
        if (hasPermission && controller != null) {
            controller.bindToLifecycle(lifecycleOwner)
        }
        onDispose {
            controller?.unbind()
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (title.isNotBlank()) {
            Text(title, color = Color.White)
        }
        if (helperText.isNotBlank()) {
            Text(helperText, color = Color.White)
        }
        if (inspectionMode) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(previewHeight),
                contentAlignment = Alignment.Center
            ) {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    drawRoundRect(
                        color = Color.White.copy(alpha = 0.15f),
                        cornerRadius = CornerRadius(12.dp.toPx())
                    )
                }
                Text("Camera Preview Placeholder", color = Color.White)
            }
            Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Button(
                    onClick = {},
                    modifier = Modifier.width(220.dp),
                    enabled = enabled,
                    colors = buttonColors
                ) {
                    Text(captureButtonLabel)
                }
            }
        } else if (hasPermission) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(previewHeight),
                contentAlignment = Alignment.Center
            ) {
                AndroidView(
                    factory = { ctx ->
                        PreviewView(ctx).apply {
                            this.controller = controller
                            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                            scaleType = PreviewView.ScaleType.FILL_CENTER
                        }
                    },
                    modifier = Modifier.fillMaxSize()
                )

                Canvas(modifier = Modifier.fillMaxSize()) {
                    val strokeWidth = 3.dp.toPx()
                    val guideWidth = size.width * 0.56f
                    val guideHeight = size.height * 0.82f
                    val centerX = size.width / 2f
                    val centerY = size.height / 2f
                    val top = centerY - guideHeight / 2f
                    val bottom = centerY + guideHeight / 2f
                    val left = centerX - guideWidth / 2f
                    val right = centerX + guideWidth / 2f
                    val cheekInset = guideWidth * 0.16f
                    val jawInset = guideWidth * 0.12f
                    val chinDip = guideHeight * 0.08f
                    val foreheadDip = guideHeight * 0.04f

                    val faceGuide = Path().apply {
                        moveTo(centerX, top + foreheadDip)
                        cubicTo(
                            right - cheekInset * 0.4f,
                            top - guideHeight * 0.02f,
                            right + cheekInset * 0.2f,
                            top + guideHeight * 0.22f,
                            right - cheekInset * 0.25f,
                            centerY - guideHeight * 0.06f
                        )
                        cubicTo(
                            right - cheekInset * 0.1f,
                            centerY + guideHeight * 0.16f,
                            right - jawInset,
                            bottom - guideHeight * 0.10f,
                            centerX + guideWidth * 0.12f,
                            bottom - chinDip
                        )
                        cubicTo(
                            centerX + guideWidth * 0.06f,
                            bottom + guideHeight * 0.02f,
                            centerX - guideWidth * 0.06f,
                            bottom + guideHeight * 0.02f,
                            centerX - guideWidth * 0.12f,
                            bottom - chinDip
                        )
                        cubicTo(
                            left + jawInset,
                            bottom - guideHeight * 0.10f,
                            left + cheekInset * 0.1f,
                            centerY + guideHeight * 0.16f,
                            left + cheekInset * 0.25f,
                            centerY - guideHeight * 0.06f
                        )
                        cubicTo(
                            left - cheekInset * 0.2f,
                            top + guideHeight * 0.22f,
                            left + cheekInset * 0.4f,
                            top - guideHeight * 0.02f,
                            centerX,
                            top + foreheadDip
                        )
                        close()
                    }

                    drawPath(
                        path = faceGuide,
                        color = Color.White.copy(alpha = 0.7f),
                        style = Stroke(
                            width = strokeWidth,
                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(30f, 15f), 0f)
                        )
                    )
                }
            }
            Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Button(
                    onClick = {
                        controller?.let {
                            nextAutoCaptureAtMillis = System.currentTimeMillis() + autoCaptureIntervalMs
                            captureToBytes(context, it, onImageCaptured)
                        }
                    },
                    modifier = Modifier.width(220.dp),
                    enabled = enabled,
                    colors = buttonColors
                ) {
                    Text(captureButtonLabel)
                }
            }
        } else {
            Text("Camera permission is required.", color = Color.White)
            Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Button(
                    onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) },
                    modifier = Modifier.width(220.dp),
                    colors = buttonColors
                ) {
                    Text("Grant Camera Access")
                }
            }
        }
    }
}

private fun captureToBytes(
    context: Context,
    controller: LifecycleCameraController,
    onImageCaptured: (ByteArray) -> Unit
) {
    val outputFile = File.createTempFile("face-capture-", ".jpg", context.cacheDir)
    val outputOptions = ImageCapture.OutputFileOptions.Builder(outputFile).build()

    controller.takePicture(
        outputOptions,
        ContextCompat.getMainExecutor(context),
        object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                onImageCaptured(outputFile.readBytes())
                outputFile.delete()
            }

            override fun onError(exception: ImageCaptureException) {
                exception.printStackTrace()
            }
        }
    )
}
