package me.whynbnb.pockito

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var cameraManager: CameraManager
    private lateinit var vibrator: Vibrator
    private var vibrateLoopHandler: Handler? = null
    private var vibrateLoopRunnable: Runnable? = null
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

        vibrator = resolveVibrator()
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pockito/vibrator",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(vibrator.hasVibrator())
                "hasAmplitudeControl" ->
                    result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            vibrator.hasAmplitudeControl(),
                    )
                "vibrate" -> {
                    val pattern = call.argument<List<Int>>("pattern") ?: emptyList()
                    val repeat = call.argument<Int>("repeat") ?: -1
                    val amplitude = call.argument<Int>("amplitude") ?: -1
                    val sharpness = call.argument<Double>("sharpness") ?: 0.5
                    try {
                        vibrate(pattern, repeat, amplitude, sharpness)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("vibrate_error", error.message, null)
                    }
                }
                "cancel" -> {
                    cancelVibrateLoop()
                    vibrator.cancel()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun resolveVibrator(): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

    private fun vibrate(pattern: List<Int>, repeat: Int, amplitude: Int, sharpness: Double) {
        if (pattern.isEmpty()) return
        cancelVibrateLoop()
        if (sharpness >= 0.75 && vibrateCrisp(pattern, repeat, amplitude)) return

        // API < 26 has no VibrationEffect; the legacy pattern treats the first value as an
        // initial OFF delay, so prepend a zero-length off segment to keep the first pulse.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            val legacy = LongArray(pattern.size + 1)
            for (index in pattern.indices) {
                legacy[index + 1] = pattern[index].toLong()
            }
            @Suppress("DEPRECATION")
            vibrator.vibrate(legacy, repeat)
            return
        }

        // On API 26+, always use the explicit amplitude overload: each segment states whether
        // it is on (amplitude > 0) or off (amplitude 0). The timings-only overload silently
        // treats the first entry as an initial off delay, which drops the first pulse.
        val hasAmplitude = vibrator.hasAmplitudeControl()
        val base = if (amplitude in 1..255) amplitude else 255
        val soft = sharpness <= 0.35 && hasAmplitude
        val weights =
            if (soft) doubleArrayOf(0.35, 0.3, 0.35) else doubleArrayOf(1.0)
        val levels =
            if (soft) doubleArrayOf(0.3, 0.65, 1.0) else doubleArrayOf(1.0)
        val shapedTimings = ArrayList<Long>()
        val shapedAmplitudes = ArrayList<Int>()
        for (index in pattern.indices) {
            val value = pattern[index].toLong()
            if (index % 2 == 1) {
                shapedTimings.add(value)
                shapedAmplitudes.add(0)
                continue
            }
            for (step in weights.indices) {
                if (step > 0) {
                    shapedTimings.add(1L)
                    shapedAmplitudes.add(0)
                }
                shapedTimings.add((value * weights[step]).toLong().coerceAtLeast(1L))
                shapedAmplitudes.add(
                    if (hasAmplitude) (base * levels[step]).toInt().coerceIn(1, 255) else 255,
                )
            }
        }
        vibrator.vibrate(
            VibrationEffect.createWaveform(
                shapedTimings.toLongArray(),
                shapedAmplitudes.toIntArray(),
                repeat,
            ),
        )
    }

    private fun vibrateCrisp(pattern: List<Int>, repeat: Int, amplitude: Int): Boolean {
        // Prefer the tuned primitive composition on Android 11+ so every pulse is a real click.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val click = VibrationEffect.Composition.PRIMITIVE_CLICK
                if (vibrator.areAllPrimitivesSupported(click)) {
                    val scale = if (amplitude in 1..255) amplitude.toFloat() / 255f else 1f
                    val composition = VibrationEffect.startComposition()
                    var pendingDelay = 0
                    var cycle = 0
                    for (index in pattern.indices) {
                        val value = pattern[index]
                        if (index % 2 == 1) {
                            pendingDelay += value
                            cycle += value
                            continue
                        }
                        composition.addPrimitive(click, scale, pendingDelay)
                        cycle += pendingDelay
                        pendingDelay = 0
                    }
                    playEffect(composition.compose(), repeat, cycle.toLong())
                    return true
                }
            } catch (_: Exception) {
                // Fall through to the scheduled system-click path below.
            }
        }
        // Android 10+ can still play each pulse as a tuned system click.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val effect = VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
            val offsets = ArrayList<Long>()
            var total = 0L
            for (index in pattern.indices) {
                val value = pattern[index].toLong()
                if (index % 2 == 0) offsets.add(total)
                total += value
            }
            if (offsets.isEmpty()) return false
            val cycle = total.coerceAtLeast(1L)
            val handler = Handler(Looper.getMainLooper())
            val runnable =
                object : Runnable {
                    override fun run() {
                        for (offset in offsets) {
                            if (offset == 0L) {
                                vibrator.vibrate(effect)
                            } else {
                                handler.postDelayed({ vibrator.vibrate(effect) }, offset)
                            }
                        }
                        if (repeat >= 0) handler.postDelayed(this, cycle)
                    }
                }
            vibrateLoopHandler = handler
            vibrateLoopRunnable = runnable
            runnable.run()
            return true
        }
        return false
    }

    private fun playEffect(effect: VibrationEffect, repeat: Int, cycle: Long) {
        vibrator.vibrate(effect)
        if (repeat >= 0) {
            val interval = cycle.coerceAtLeast(1L)
            val handler = Handler(Looper.getMainLooper())
            val runnable =
                object : Runnable {
                    override fun run() {
                        vibrator.vibrate(effect)
                        handler.postDelayed(this, interval)
                    }
                }
            vibrateLoopHandler = handler
            vibrateLoopRunnable = runnable
            handler.postDelayed(runnable, interval)
        }
    }

    private fun cancelVibrateLoop() {
        vibrateLoopRunnable?.let { vibrateLoopHandler?.removeCallbacks(it) }
        vibrateLoopHandler?.removeCallbacksAndMessages(null)
        vibrateLoopRunnable = null
        vibrateLoopHandler = null
    }

    override fun onDestroy() {
        cancelVibrateLoop()
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
