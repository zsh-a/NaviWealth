/// Native (iOS / Android) [NotificationService] backed by
/// `flutter_local_notifications`. The plugin object is a singleton —
/// we wrap it so the rest of the app gets a stable Dart interface
/// and so a web build can swap it out via conditional import.
library;

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_service.dart';

NotificationService createNotificationService() => _LocalNotificationService();

class _LocalNotificationService implements NotificationService {
  _LocalNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  final Set<String> _createdAndroidChannelIds = <String>{};

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
      ),
    );
    _initialized = true;
  }

  Future<void> _ensureAndroidChannel(NotificationChannelSpec channel) async {
    await _ensureInitialized();
    if (!Platform.isAndroid) return;
    if (!_createdAndroidChannelIds.add(channel.id)) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        channel.id,
        channel.name,
        description: channel.description,
        importance: Importance.defaultImportance,
      ),
    );
  }

  @override
  Future<bool> isAvailable() async => Platform.isIOS || Platform.isAndroid;

  @override
  Future<bool> hasPermissions() async {
    if (!await isAvailable()) return false;
    await _ensureInitialized();
    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted = await ios?.checkPermissions();
      return granted?.isEnabled ?? false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? false;
  }

  @override
  Future<bool> requestPermissions() async {
    if (!await isAvailable()) return false;
    await _ensureInitialized();
    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required NotificationChannelSpec channel,
    String? payload,
  }) async {
    if (!await isAvailable()) return;
    await _ensureAndroidChannel(channel);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      ),
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!await isAvailable()) return;
    await _ensureInitialized();
    await _plugin.cancel(id: id);
  }
}
