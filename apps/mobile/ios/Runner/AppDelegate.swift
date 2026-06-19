import Flutter
import HealthKit
import UIKit
import receive_sharing_intent
import workmanager_apple  // D-2.5b — periodic Morning Briefing scheduling

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let healthStore = HKHealthStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // D-2.5b — register the background-task identifier so iOS
    // BGTaskScheduler can fire it. Identifier must match the
    // Info.plist `BGTaskSchedulerPermittedIdentifiers` entry and
    // the Dart `Workmanager().registerPeriodicTask(uniqueName, …)`
    // task name.
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "com.naviwealth.morningBriefing"
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
