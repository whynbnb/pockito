import AVFoundation
import AudioToolbox
import CoreHaptics
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Play the frequency generator through the main speaker even when the
    // ring/silent switch is on, and mix with other audio instead of stopping it.
    try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PockitoFlashlight") {
      FlashlightChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PockitoVibrator") {
      VibratorChannel.register(with: registrar)
    }
  }
}

final class FlashlightChannel {
  private static var retained: FlashlightChannel?

  private let channel: FlutterMethodChannel

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlashlightChannel(messenger: registrar.messenger())
    retained = instance
  }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "pockito/flashlight", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private var device: AVCaptureDevice? {
    AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      if let device = device, device.hasTorch {
        result(device.isTorchAvailable)
      } else {
        result(false)
      }
    case "getMaxStrength":
      if let device = device, device.hasTorch {
        result(10)
      } else {
        result(0)
      }
    case "isTorchOn":
      result(device?.isTorchActive ?? false)
    case "setTorch":
      let arguments = call.arguments as? [String: Any]
      let on = arguments?["on"] as? Bool ?? false
      let strength = arguments?["strength"] as? Int
      setTorch(on: on, strength: strength, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setTorch(on: Bool, strength: Int?, result: @escaping FlutterResult) {
    guard let device = device, device.hasTorch else {
      result(
        FlutterError(code: "torch_unavailable", message: "No torch on this device", details: nil)
      )
      return
    }
    guard device.isTorchAvailable else {
      result(FlutterError(code: "torch_busy", message: "Torch is currently unavailable", details: nil))
      return
    }
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }
      if on {
        if let strength = strength, strength > 0 {
          let maxLevel = Float(10)
          let level = max(Float(0.01), min(1.0, Float(strength) / maxLevel))
          try device.setTorchModeOn(level: level)
        } else {
          try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
        }
      } else {
        device.torchMode = .off
      }
      result(nil)
    } catch {
      result(FlutterError(code: "torch_error", message: error.localizedDescription, details: nil))
    }
  }
}

final class VibratorChannel {
  private static var retained: VibratorChannel?

  private let channel: FlutterMethodChannel
  private var engine: CHHapticEngine?
  private var player: CHHapticAdvancedPatternPlayer?

  private var supportsHaptics: Bool {
    CHHapticEngine.capabilitiesForHardware().supportsHaptics
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = VibratorChannel(messenger: registrar.messenger())
    retained = instance
  }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "pockito/vibrator", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(supportsHaptics || UIDevice.current.userInterfaceIdiom == .phone)
    case "hasAmplitudeControl":
      result(supportsHaptics)
    case "vibrate":
      let arguments = call.arguments as? [String: Any]
      let pattern = arguments?["pattern"] as? [Int] ?? []
      let repeatIndex = arguments?["repeat"] as? Int ?? -1
      let amplitude = arguments?["amplitude"] as? Int ?? -1
      let sharpness = arguments?["sharpness"] as? Double ?? 0.5
      vibrate(
        pattern: pattern,
        repeatIndex: repeatIndex,
        amplitude: amplitude,
        sharpness: sharpness,
        result: result
      )
    case "cancel":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func vibrate(
    pattern: [Int],
    repeatIndex: Int,
    amplitude: Int,
    sharpness: Double,
    result: @escaping FlutterResult
  ) {
    guard !pattern.isEmpty else {
      result(nil)
      return
    }
    stop()
    guard supportsHaptics else {
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
      result(nil)
      return
    }
    do {
      let engine = try resolveEngine()
      let events = makeEvents(pattern: pattern, amplitude: amplitude, sharpness: sharpness)
      let hapticPattern = try CHHapticPattern(events: events, parameters: [])
      let player = try engine.makeAdvancedPlayer(with: hapticPattern)
      player.loopEnabled = repeatIndex >= 0
      try engine.start()
      try player.start(atTime: CHHapticTimeImmediate)
      self.player = player
      result(nil)
    } catch {
      result(FlutterError(code: "vibrate_error", message: error.localizedDescription, details: nil))
    }
  }

  private func makeEvents(pattern: [Int], amplitude: Int, sharpness: Double) -> [CHHapticEvent] {
    let intensity = amplitude >= 0 ? Float(max(1, min(255, amplitude))) / 255.0 : 1.0
    let sharp = Float(max(0.0, min(1.0, sharpness)))
    var events: [CHHapticEvent] = []
    var time: TimeInterval = 0
    for (index, value) in pattern.enumerated() {
      let duration = TimeInterval(value) / 1000.0
      if index % 2 == 0 {
        if duration < 0.1 || sharp >= 0.9 {
          events.append(
            CHHapticEvent(
              eventType: .hapticTransient,
              parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharp),
              ],
              relativeTime: time
            )
          )
        } else {
          events.append(
            CHHapticEvent(
              eventType: .hapticContinuous,
              parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharp),
              ],
              relativeTime: time,
              duration: duration
            )
          )
        }
      }
      time += duration
    }
    return events
  }

  private func resolveEngine() throws -> CHHapticEngine {
    if let engine = engine {
      return engine
    }
    let engine = try CHHapticEngine()
    engine.playsHapticsOnly = true
    engine.stoppedHandler = { [weak self] _ in
      self?.player = nil
    }
    engine.resetHandler = { [weak self] in
      try? self?.engine?.start()
    }
    self.engine = engine
    return engine
  }

  private func stop() {
    try? player?.stop(atTime: CHHapticTimeImmediate)
    player = nil
  }
}
