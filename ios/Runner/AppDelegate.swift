import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ReefFlashlight") {
      FlashlightChannel.register(with: registrar)
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
    channel = FlutterMethodChannel(name: "reef/flashlight", binaryMessenger: messenger)
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
