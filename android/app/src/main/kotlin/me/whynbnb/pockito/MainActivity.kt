package me.whynbnb.pockito

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var cameraManager: CameraManager
    private var torchCameraId: String? = null
    private var torchOn = false

    private val torchCallback =
        object : CameraManager.TorchCallback() {
            override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
                if (cameraId == torchCameraId) torchOn = enabled
            }

            override fun onTorchModeUnavailable(cameraId: String) {
                if (cameraId == torchCameraId) torchOn = false
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        torchCameraId = findTorchCameraId()
        cameraManager.registerTorchCallback(torchCallback, Handler(Looper.getMainLooper()))

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pockito/flashlight",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(torchCameraId != null)
                "getMaxStrength" -> result.success(maxTorchStrength())
                "isTorchOn" -> result.success(torchOn)
                "setTorch" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    val strength = call.argument<Int>("strength")
                    try {
                        setTorch(on, strength)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("torch_error", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (::cameraManager.isInitialized) {
            cameraManager.unregisterTorchCallback(torchCallback)
        }
        super.onDestroy()
    }

    private fun findTorchCameraId(): String? {
        return try {
            cameraManager.cameraIdList.firstOrNull { id ->
                cameraManager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun maxTorchStrength(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return 0
        val id = torchCameraId ?: return 0
        return try {
            cameraManager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.FLASH_INFO_STRENGTH_MAXIMUM_LEVEL) ?: 0
        } catch (_: Exception) {
            0
        }
    }

    private fun setTorch(on: Boolean, strength: Int?) {
        val id = torchCameraId ?: throw IllegalStateException("No torch camera")
        if (!on) {
            cameraManager.setTorchMode(id, false)
            torchOn = false
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && strength != null) {
            val max = maxTorchStrength()
            if (max > 1) {
                cameraManager.turnOnTorchWithStrengthLevel(id, strength.coerceIn(1, max))
                torchOn = true
                return
            }
        }
        cameraManager.setTorchMode(id, true)
        torchOn = true
    }
}
