import Flutter
import UIKit

/// Streams a bundled Flutter asset out of the app bundle to a file in small
/// chunks. The Dart AssetBundle API only loads whole files into memory, which
/// OOM-kills the app for the 668 MB food database; Bundle streams it instead.
/// Mirrors the Android implementation in MainActivity.kt.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let channelName = "com.trsonn.macrotrack/asset_copy"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: channelName, binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        Self.handle(call: call, result: result)
      }
    }
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "copyAsset" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let asset = args["asset"] as? String,
      let dest = args["dest"] as? String
    else {
      result(FlutterError(code: "args", message: "asset and dest required", details: nil))
      return
    }
    // Dart-side asset paths are relative to the bundle's flutter_assets dir.
    let fm = FileManager.default
    let candidates = [
      "Frameworks/App.framework/flutter_assets/\(asset)",
      "flutter_assets/\(asset)",
      asset,
    ]
    let srcPath = candidates.lazy
      .map { Bundle.main.path(forResource: $0, ofType: nil) }
      .first { $0 != nil }
    guard let src = srcPath else {
      result(FlutterError(code: "io", message: "asset not found: \(asset)", details: nil))
      return
    }
    let tmp = dest + ".tmp"
    do {
      try? fm.removeItem(atPath: tmp)
      // fs.copyItem streams through the kernel buffer cache in pages; it does
      // NOT load the whole file into memory (unlike Dart's rootBundle).
      try fm.copyItem(atPath: src, toPath: tmp)
      if fm.fileExists(atPath: dest) {
        try fm.removeItem(atPath: dest)
      }
      try fm.moveItem(atPath: tmp, toPath: dest)
      // Flush to disk (best-effort equivalent of Android's fd.sync()).
      if let fh = FileHandle(forWritingAtPath: dest) {
        try? fh.synchronize()
        fh.closeFile()
      }
      result(Int64(1))
    } catch {
      try? fm.removeItem(atPath: tmp)
      result(FlutterError(code: "io", message: error.localizedDescription, details: nil))
    }
  }
}
