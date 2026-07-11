import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications: the plugin does NOT claim the notification-
    // center delegate itself; without this line iOS silently drops every
    // notification shown while the app is foregrounded.
    UNUserNotificationCenter.current().delegate = self

    // Workmanager/BGTaskScheduler: handlers must be registered before launch
    // finishes. Identifiers mirror BGTaskSchedulerPermittedIdentifiers in
    // Info.plist and the unique task names used on the Dart side.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "dailySpendingSummaryUnique", frequency: NSNumber(value: 15 * 60))
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "sharedExpenseNotificationCatchupUnique", frequency: NSNumber(value: 15 * 60))
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "widgetMidnightRefreshUnique", frequency: NSNumber(value: 30 * 60))
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "dataSyncDrainUnique", frequency: NSNumber(value: 15 * 60))
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "dataSyncImmediateDrainUnique")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
