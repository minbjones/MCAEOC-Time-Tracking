package com.example.employeetimetracking

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.employeetimetracking.ui.EmployeeTimeTrackingApp
import com.example.employeetimetracking.ui.MainViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val mainViewModel: MainViewModel = viewModel()
            EmployeeTimeTrackingApp(mainViewModel)
        }
    }
}
