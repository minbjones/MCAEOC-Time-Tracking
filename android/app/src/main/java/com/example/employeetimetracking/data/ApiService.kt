package com.example.employeetimetracking.data

import com.example.employeetimetracking.BuildConfig
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.GET
import retrofit2.http.Body
import retrofit2.http.POST

interface MobileApiService {
    @GET("api/mobile/employees")
    suspend fun employees(): List<EmployeeListItem>

    @POST("api/mobile/auth/login")
    suspend fun login(@Body payload: LoginRequest): LoginResponse

    @POST("api/mobile/face/enroll")
    suspend fun enrollFace(@Body payload: FaceEnrollmentRequest): ApiMessageResponse

    @POST("api/mobile/clock/verify-and-clock")
    suspend fun verifyAndClock(@Body payload: FaceClockRequest): FaceClockResponse

    @POST("api/mobile/clock/identify-and-clock")
    suspend fun identifyAndClock(@Body payload: IdentifyClockRequest): FaceClockResponse
}

object ApiClient {
    private val authInterceptor = Interceptor { chain ->
        val request = chain.request().newBuilder()
            .addHeader("x-api-key", BuildConfig.MOBILE_API_KEY)
            .build()
        chain.proceed(request)
    }

    private val loggingInterceptor = HttpLoggingInterceptor().apply {
        level = HttpLoggingInterceptor.Level.BODY
    }

    private val client = OkHttpClient.Builder()
        .addInterceptor(authInterceptor)
        .addInterceptor(loggingInterceptor)
        .build()

    val service: MobileApiService = Retrofit.Builder()
        .baseUrl(BuildConfig.BASE_URL)
        .client(client)
        .addConverterFactory(GsonConverterFactory.create())
        .build()
        .create(MobileApiService::class.java)
}
