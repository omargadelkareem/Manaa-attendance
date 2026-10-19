package com.example.manaa_attendance



import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "manaa/location"
    private val permissionRequestCode = 9001

    private var pendingResult: MethodChannel.Result? = null

    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "checkPermission" -> {
                    result.success(hasLocationPermission())
                }

                "isLocationEnabled" -> {
                    result.success(isLocationEnabled())
                }

                "getCurrentLocation" -> {
                    getCurrentLocation(result)
                }

                "openLocationSettings" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_LOCATION_SOURCE_SETTINGS
                        )
                    )

                    result.success(null)
                }

                "openAppSettings" -> {
                    val intent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                    )

                    intent.data = Uri.parse(
                        "package:$packageName"
                    )

                    startActivity(intent)

                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        )

        val coarse = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )

        return fine == PackageManager.PERMISSION_GRANTED ||
                coarse == PackageManager.PERMISSION_GRANTED
    }

    private fun isLocationEnabled(): Boolean {
        val manager = getSystemService(
            Context.LOCATION_SERVICE
        ) as LocationManager

        return try {
            manager.isProviderEnabled(
                LocationManager.GPS_PROVIDER
            ) ||
                    manager.isProviderEnabled(
                        LocationManager.NETWORK_PROVIDER
                    )
        } catch (_: Exception) {
            false
        }
    }

    private fun getCurrentLocation(
        result: MethodChannel.Result
    ) {
        if (pendingResult != null) {
            result.error(
                "LOCATION_BUSY",
                "Location request already running.",
                null
            )
            return
        }

        if (!hasLocationPermission()) {
            pendingResult = result

            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ),
                permissionRequestCode
            )

            return
        }

        if (!isLocationEnabled()) {
            result.error(
                "LOCATION_DISABLED",
                "Location services are disabled.",
                null
            )
            return
        }

        requestFastLocation(result)
    }

    private fun requestFastLocation(
        result: MethodChannel.Result
    ) {
        val manager = getSystemService(
            Context.LOCATION_SERVICE
        ) as LocationManager

        /*
         * أولاً:
         * نحاول استخدام موقع حديث جدًا موجود بالفعل.
         *
         * لو عمره <= 15 ثانية ودقته <= 50 متر
         * نرجعه فورًا بدون انتظار GPS جديد.
         */
        val cached = getBestLastKnownLocation(manager)

        if (cached != null) {
            val age =
                System.currentTimeMillis() - cached.time

            if (
                age in 0..15_000 &&
                cached.accuracy <= 50f
            ) {
                sendLocation(
                    result,
                    cached,
                    true
                )

                return
            }
        }

        /*
         * لو مفيش cached حديث:
         * نطلب GPS + Network معًا.
         *
         * أول موقع جيد نأخذه.
         * أقصى انتظار 5 ثواني.
         */

        var completed = false

        val receivedLocations =
            mutableListOf<Location>()

        lateinit var listener: LocationListener

        fun finishWith(
            location: Location,
            cachedValue: Boolean = false
        ) {
            if (completed) return

            completed = true

            handler.removeCallbacksAndMessages(
                null
            )

            try {
                manager.removeUpdates(listener)
            } catch (_: Exception) {
            }

            sendLocation(
                result,
                location,
                cachedValue
            )
        }

        listener = object : LocationListener {

            override fun onLocationChanged(
                location: Location
            ) {
                if (completed) return

                receivedLocations.add(location)

                /*
                 * Accuracy <= 35m:
                 * ممتاز للحضور → لا ننتظر أكثر.
                 */
                if (location.accuracy <= 35f) {
                    finishWith(location)
                }
            }

            override fun onProviderEnabled(
                provider: String
            ) {
            }

            override fun onProviderDisabled(
                provider: String
            ) {
            }

            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(
                provider: String?,
                status: Int,
                extras: Bundle?
            ) {
            }
        }

        try {
            if (
                manager.isProviderEnabled(
                    LocationManager.NETWORK_PROVIDER
                )
            ) {
                manager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    0L,
                    0f,
                    listener,
                    Looper.getMainLooper()
                )
            }

            if (
                manager.isProviderEnabled(
                    LocationManager.GPS_PROVIDER
                )
            ) {
                manager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    0L,
                    0f,
                    listener,
                    Looper.getMainLooper()
                )
            }

            /*
             * Timeout قصير.
             *
             * بعد 5 ثواني:
             * نختار أفضل Location وصل.
             */
            handler.postDelayed(
                {
                    if (completed) {
                        return@postDelayed
                    }

                    val best =
                        chooseBestLocation(
                            receivedLocations
                        )
                            ?: cached

                    if (best != null) {
                        finishWith(
                            best,
                            best === cached
                        )
                    } else {
                        completed = true

                        try {
                            manager.removeUpdates(
                                listener
                            )
                        } catch (_: Exception) {
                        }

                        result.error(
                            "LOCATION_UNAVAILABLE",
                            "Unable to determine current location.",
                            null
                        )
                    }
                },
                5000L
            )

        } catch (
            e: SecurityException
        ) {
            result.error(
                "PERMISSION_DENIED",
                e.message,
                null
            )
        } catch (
            e: Exception
        ) {
            result.error(
                "LOCATION_UNAVAILABLE",
                e.message,
                null
            )
        }
    }

    private fun getBestLastKnownLocation(
        manager: LocationManager
    ): Location? {
        val locations =
            mutableListOf<Location>()

        try {
            if (
                manager.isProviderEnabled(
                    LocationManager.GPS_PROVIDER
                )
            ) {
                manager.getLastKnownLocation(
                    LocationManager.GPS_PROVIDER
                )?.let {
                    locations.add(it)
                }
            }
        } catch (_: Exception) {
        }

        try {
            if (
                manager.isProviderEnabled(
                    LocationManager.NETWORK_PROVIDER
                )
            ) {
                manager.getLastKnownLocation(
                    LocationManager.NETWORK_PROVIDER
                )?.let {
                    locations.add(it)
                }
            }
        } catch (_: Exception) {
        }

        return chooseBestLocation(locations)
    }

    private fun chooseBestLocation(
        locations: List<Location>
    ): Location? {
        if (locations.isEmpty()) {
            return null
        }

        return locations.minWithOrNull(
            compareBy<Location> {
                it.accuracy
            }.thenByDescending {
                it.time
            }
        )
    }

    private fun sendLocation(
        result: MethodChannel.Result,
        location: Location,
        cached: Boolean
    ) {
        result.success(
            mapOf(
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "accuracy" to
                        location.accuracy.toDouble(),
                "timestamp" to location.time,
                "provider" to
                        (location.provider ?: "unknown"),
                "cached" to cached
            )
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults
        )

        if (
            requestCode != permissionRequestCode
        ) {
            return
        }

        val result = pendingResult

        pendingResult = null

        if (result == null) {
            return
        }

        if (hasLocationPermission()) {
            requestFastLocation(result)
        } else {
            result.error(
                "PERMISSION_DENIED",
                "Location permission denied.",
                null
            )
        }
    }
}