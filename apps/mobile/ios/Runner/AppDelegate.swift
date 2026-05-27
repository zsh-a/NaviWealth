import Flutter
import UIKit
import workmanager  // D-2.5b — periodic Morning Briefing scheduling

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
