import Flutter
import AVFoundation
import HealthKit
import UIKit
import receive_sharing_intent
import workmanager_apple  // HealthOS background task scheduling

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let healthStore = HKHealthStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register background-task identifiers so iOS BGTaskScheduler can fire
    // them. Identifiers must match the
    // Info.plist `BGTaskSchedulerPermittedIdentifiers` entry and
    // the Dart `Workmanager().registerPeriodicTask(uniqueName, …)`
    // task names.
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "com.naviwealth.lifeAttention"
    )
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "com.naviwealth.executionReview"
    )
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "com.naviwealth.garminSync"
    )
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "com.naviwealth.healthPlatformSync"
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let sharingIntent = SwiftReceiveSharingIntentPlugin.instance
    if sharingIntent.hasMatchingSchemePrefix(url: url) {
      return sharingIntent.application(app, open: url, options: options)
    }
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let videoRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "NaviVideoFrames") {
      NaviVideoFrames.install(messenger: videoRegistrar.messenger())
    }
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NaviHealthKit") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.naviwealth.healthkit",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "requestVo2MaxAuthorization":
        self?.requestVo2MaxAuthorization(result: result)
      case "readVo2Max":
        self?.readVo2Max(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func vo2MaxType() -> HKQuantityType? {
    HKObjectType.quantityType(forIdentifier: .vo2Max)
  }

  private func requestVo2MaxAuthorization(result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable(), let type = vo2MaxType() else {
      result(false)
      return
    }
    healthStore.requestAuthorization(toShare: [], read: [type]) { success, _ in
      result(success)
    }
  }

  private func readVo2Max(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable(), let type = vo2MaxType() else {
      result([])
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let fromMs = args["from"] as? NSNumber,
      let toMs = args["to"] as? NSNumber
    else {
      result(FlutterError(code: "bad_args", message: "from/to milliseconds are required", details: nil))
      return
    }

    let start = Date(timeIntervalSince1970: fromMs.doubleValue / 1000.0)
    let end = Date(timeIntervalSince1970: toMs.doubleValue / 1000.0)
    let predicate = HKQuery.predicateForSamples(
      withStart: start,
      end: end,
      options: [.strictStartDate]
    )
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
    let unit = HKUnit
      .literUnit(with: .milli)
      .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.minute()))

    let query = HKSampleQuery(
      sampleType: type,
      predicate: predicate,
      limit: HKObjectQueryNoLimit,
      sortDescriptors: [sort]
    ) { _, samples, error in
      if let error = error {
        result(FlutterError(code: "healthkit_error", message: error.localizedDescription, details: nil))
        return
      }
      let rows = (samples as? [HKQuantitySample] ?? []).map { sample in
        [
          "uuid": sample.uuid.uuidString,
          "measured_at_ms": Int(sample.startDate.timeIntervalSince1970 * 1000.0),
          "value": sample.quantity.doubleValue(for: unit),
          "source_device": sample.sourceRevision.source.name,
        ] as [String: Any]
      }
      result(rows)
    }
    healthStore.execute(query)
  }
}

/// Local, bounded still-image extraction. Decode work never blocks the UI queue.
private enum NaviVideoFrames {
  static func install(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.naviwealth/video_frames", binaryMessenger: messenger)
    let queue = DispatchQueue(label: "com.naviwealth.video-frames", qos: .userInitiated)
    channel.setMethodCallHandler { call, result in
      guard call.method == "extract" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
        let path = args["path"] as? String, path.hasPrefix("/") else {
        result(FlutterError(code: "unreadable", message: "A local video file is required", details: nil))
        return
      }
      queue.async {
        do {
          let attributes = try FileManager.default.attributesOfItem(atPath: path)
          let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
          guard size > 0, size <= 50 * 1024 * 1024 else {
            throw FrameError(code: "video_size")
          }
          let asset = AVURLAsset(url: URL(fileURLWithPath: path))
          let seconds = CMTimeGetSeconds(asset.duration)
          guard seconds.isFinite, seconds > 0 else { throw FrameError(code: "unreadable") }
          guard seconds <= 10 else { throw FrameError(code: "video_duration") }
          guard let track = asset.tracks(withMediaType: .video).first,
            track.naturalSize.width * track.naturalSize.height <= 40_000_000 else {
            throw FrameError(code: "unreadable")
          }
          let generator = AVAssetImageGenerator(asset: asset)
          generator.appliesPreferredTrackTransform = true
          generator.maximumSize = CGSize(width: 1280, height: 1280)
          generator.requestedTimeToleranceBefore = .zero
          generator.requestedTimeToleranceAfter = .zero
          var frames = [[String: Any]]()
          for index in 0..<8 {
            try autoreleasepool {
              let time = seconds * Double(index * 2 + 1) / 16
              var actual = CMTime.zero
              let cgImage = try generator.copyCGImage(
                at: CMTime(seconds: time, preferredTimescale: 600), actualTime: &actual)
              guard let bytes = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85),
                bytes.count <= 2 * 1024 * 1024 else { throw FrameError(code: "unreadable") }
              frames.append([
                "time_ms": Int((CMTimeGetSeconds(actual) * 1000).rounded()),
                "bytes": FlutterStandardTypedData(bytes: bytes),
              ])
            }
          }
          let response: [String: Any] = [
            "duration_ms": Int((seconds * 1000).rounded()), "frames": frames,
          ]
          DispatchQueue.main.async { result(response) }
        } catch {
          let code = (error as? FrameError)?.code ?? "unreadable"
          DispatchQueue.main.async {
            result(FlutterError(code: code, message: "Unable to extract video frames", details: nil))
          }
        }
      }
    }
  }

  private struct FrameError: Error { let code: String }
}
