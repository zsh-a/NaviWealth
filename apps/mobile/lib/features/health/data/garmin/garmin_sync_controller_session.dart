part of 'garmin_sync_controller.dart';

mixin GarminSyncControllerSessionMixin on Notifier<GarminSyncState> {
  GarminBridge get _bridge;
  GarminTokenStore get _tokenStore;
  bool get _initialized;
  set _initialized(bool value);
  GarminRegion? get _initializedRegion;
  set _initializedRegion(GarminRegion? value);
  StreamSubscription<GarminSyncProgress>? get _syncSub;
  set _syncSub(StreamSubscription<GarminSyncProgress>? value);

  /// Try to restore a persisted Garmin session on startup.
  Future<void> _restoreSession() async {
    final stored = await _tokenStore.load();
    if (stored == null) return;

    state = const GarminRestoring();
    try {
      await _ensureInit(storedTokenJson: stored);
      final authState = await _bridge.authState();
      if (authState.canMakeRequests) {
        state = const GarminConnected();
      } else {
        final issue = garminRestoreAuthIssue(authState);
        await _clearStaleSession();
        state = GarminError(issue);
      }
    } catch (e) {
      await _clearStaleSession();
      state = GarminError(GarminSyncIssue.fromLegacyMessage(e.toString()));
    }
  }

  /// Ensure the Rust-side Garmin client is initialized.
  /// Must be called before any other bridge method.
  Future<void> _ensureInit({String? storedTokenJson}) async {
    final region = ref.read(garminRegionProvider);
    if (_initialized && _initializedRegion == region) return;
    await _bridge.init(storedTokenJson: storedTokenJson, isCn: region.isCn);
    _initialized = true;
    _initializedRegion = region;
  }

  /// Connect with email/password.
  Future<void> connect(String email, String password) async {
    state = GarminSyncing(startedAt: DateTime.now().toUtc());
    try {
      await _ensureInit();
      final result = await _bridge.authenticate(email, password);
      switch (result.type) {
        case GarminAuthResultType.authenticated:
          await _persistSession();
          state = const GarminConnected();
        case GarminAuthResultType.mfaRequired:
          state = const GarminPendingMfa();
        case GarminAuthResultType.failed:
          state = GarminError(
            GarminSyncIssue.fromLegacyMessage(
              result.errorMessage ?? 'auth failed',
            ),
          );
      }
    } catch (e) {
      state = GarminError(GarminSyncIssue.fromLegacyMessage(e.toString()));
    }
  }

  /// Submit MFA code.
  Future<void> submitMfa(String code) async {
    try {
      await _ensureInit();
      final result = await _bridge.submitMfa(code);
      switch (result.type) {
        case GarminAuthResultType.authenticated:
          await _persistSession();
          state = const GarminConnected();
        case GarminAuthResultType.mfaRequired:
          state = const GarminPendingMfa();
        case GarminAuthResultType.failed:
          state = GarminError(
            GarminSyncIssue.fromLegacyMessage(
              result.errorMessage ?? 'MFA failed',
            ),
          );
      }
    } catch (e) {
      state = GarminError(GarminSyncIssue.fromLegacyMessage(e.toString()));
    }
  }

  Future<bool> _ensureSessionForSync(AppLogger logger) async {
    final stored = _initialized ? null : await _tokenStore.load();
    if (!_initialized && stored == null) {
      logger.i('HealthOS Garmin sync skipped: no persisted session');
      return false;
    }
    await _ensureInit(storedTokenJson: stored);
    final authState = await _bridge.authState();
    if (authState.canMakeRequests) return true;

    final issue = garminRestoreAuthIssue(authState);
    if (issue.requiresReconnect) {
      await _clearStaleSession();
      logger.w('HealthOS Garmin stale session cleared before sync');
    }
    state = GarminError(issue);
    return false;
  }

  Future<void> _clearStaleSession() async {
    await _tokenStore.clear();
    _initialized = false;
    _initializedRegion = null;
  }

  /// Cancel an in-progress sync.
  Future<void> cancelSync() async {
    await _bridge.cancelSync();
    await _syncSub?.cancel();
    _syncSub = null;
    state = const GarminConnected();
  }

  /// Disconnect and clear credentials.
  Future<void> disconnect() async {
    try {
      await _ensureInit();
      await _bridge.logout();
      await _clearStaleSession();
      state = const GarminInitial();
    } catch (e) {
      state = GarminError(GarminSyncIssue.fromLegacyMessage(e.toString()));
    }
  }

  /// Export session from Rust and persist to secure storage.
  Future<void> _persistSession() async {
    try {
      final json = await _bridge.exportSession();
      if (json != null) await _tokenStore.save(json);
    } catch (_) {
      // Non-fatal: user can still use the session this launch.
    }
  }
}
