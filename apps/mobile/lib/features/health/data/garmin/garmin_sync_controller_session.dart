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
  GarminSavedCredentials? get _pendingCredentials;
  set _pendingCredentials(GarminSavedCredentials? value);
  bool get _pendingRememberPassword;
  set _pendingRememberPassword(bool value);

  /// Try to restore a persisted Garmin session on startup.
  Future<void> _restoreSession() async {
    try {
      final ownerUserId = await _ownerUserId();
      final region = ref.read(garminRegionProvider);
      final stored = await _tokenStore.loadSession(
        ownerUserId: ownerUserId,
        region: region,
      );
      if (stored == null) {
        final credentials = await _tokenStore.loadCredentials(
          ownerUserId: ownerUserId,
        );
        if (credentials == null) return;
        state = const GarminRestoring();
        final recovered = await _recoverWithSavedCredentials();
        if (!recovered && state is! GarminPendingMfa && state is! GarminError) {
          state = GarminError(
            GarminSyncIssue.fromLegacyMessage('Garmin token expired'),
          );
        }
        return;
      }

      state = const GarminRestoring();
      final authState = await _ensureInit(storedTokenJson: stored);
      if (authState.canMakeRequests) {
        await _persistSession();
        state = _restoredConnectedState(ownerUserId);
      } else {
        final issue = garminRestoreAuthIssue(authState);
        await _clearStaleSession();
        final recovered = await _recoverWithSavedCredentials();
        if (!recovered && state is! GarminPendingMfa && state is! GarminError) {
          state = GarminError(issue);
        }
      }
    } catch (e) {
      await _clearStaleSession();
      final recovered = await _recoverWithSavedCredentials();
      if (!recovered && state is! GarminPendingMfa && state is! GarminError) {
        state = GarminError(GarminSyncIssue.fromLegacyMessage(e.toString()));
      }
    }
  }

  /// Ensure the Rust-side Garmin client is initialized.
  /// Must be called before any other bridge method.
  Future<GarminAuthState> _ensureInit({String? storedTokenJson}) async {
    final region = ref.read(garminRegionProvider);
    if (_initialized && _initializedRegion == region) {
      return _bridge.authState();
    }
    final authState = await _bridge.init(
      storedTokenJson: storedTokenJson,
      isCn: region.isCn,
    );
    _initialized = true;
    _initializedRegion = region;
    return authState;
  }

  /// Connect with email/password.
  Future<void> connect(
    String email,
    String password, {
    required bool rememberPassword,
  }) async {
    state = GarminSyncing(startedAt: DateTime.now().toUtc());
    final credentials = GarminSavedCredentials(
      email: email,
      password: password,
      region: ref.read(garminRegionProvider),
    );
    _pendingCredentials = credentials;
    _pendingRememberPassword = rememberPassword;
    try {
      await _ensureInit();
      final result = await _bridge.authenticate(
        credentials.email,
        credentials.password,
      );
      switch (result.type) {
        case GarminAuthResultType.authenticated:
          await _persistSession();
          await _commitCredentialPreference();
          await _clearSyncStatus();
          state = const GarminConnected();
        case GarminAuthResultType.mfaRequired:
          state = const GarminPendingMfa();
        case GarminAuthResultType.failed:
          _clearPendingCredentials();
          state = GarminError(
            GarminSyncIssue.fromLegacyMessage(
              result.errorMessage ?? 'auth failed',
            ),
          );
      }
    } catch (e) {
      _clearPendingCredentials();
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
          await _commitCredentialPreference();
          state = await _restoredConnectedStateForCurrentOwner();
        case GarminAuthResultType.mfaRequired:
          state = const GarminPendingMfa();
        case GarminAuthResultType.failed:
          _clearPendingCredentials();
          state = GarminError(
            GarminSyncIssue.fromLegacyMessage(
              result.errorMessage ?? 'MFA failed',
            ),
          );
      }
    } catch (e) {
      _clearPendingCredentials();
      state = GarminError(GarminSyncIssue.fromLegacyMessage(e.toString()));
    }
  }

  Future<bool> _ensureSessionForSync(AppLogger logger) async {
    final ownerUserId = await _ownerUserId();
    final region = ref.read(garminRegionProvider);
    final stored = _initialized
        ? null
        : await _tokenStore.loadSession(
            ownerUserId: ownerUserId,
            region: region,
          );
    if (!_initialized && stored == null) {
      logger.i('HealthOS Garmin sync: no persisted session, trying recovery');
      return _recoverWithSavedCredentials(logger: logger);
    }
    final authState = await _ensureInit(storedTokenJson: stored);
    if (authState.canMakeRequests) {
      await _persistSession();
      return true;
    }

    final issue = garminRestoreAuthIssue(authState);
    if (issue.requiresReconnect) {
      await _clearStaleSession();
      logger.w('HealthOS Garmin stale session cleared before sync');
    }
    final recovered = await _recoverWithSavedCredentials(logger: logger);
    if (!recovered && state is! GarminPendingMfa && state is! GarminError) {
      state = GarminError(issue);
    }
    return recovered;
  }

  Future<void> _clearStaleSession() async {
    final ownerUserId = await _ownerUserId();
    await _tokenStore.clearSession(
      ownerUserId: ownerUserId,
      region: ref.read(garminRegionProvider),
    );
    _initialized = false;
    _initializedRegion = null;
  }

  /// Cancel an in-progress sync.
  Future<void> cancelSync() async {
    await _bridge.cancelSync();
    await _syncSub?.cancel();
    _syncSub = null;
    state = await _restoredConnectedStateForCurrentOwner();
  }

  /// Disconnect and clear credentials.
  Future<void> disconnect() async {
    try {
      final ownerUserId = await _ownerUserId();
      if (_initialized) await _bridge.logout();
      await _tokenStore.clearAll(ownerUserId: ownerUserId);
      await GarminSyncStatusStore(
        ref.read(sharedPreferencesProvider),
      ).clear(ownerUserId);
      _initialized = false;
      _initializedRegion = null;
      _clearPendingCredentials();
      state = const GarminInitial();
    } catch (e) {
      state = GarminError(GarminSyncIssue.fromLegacyMessage(e.toString()));
    }
  }

  /// Export session from Rust and persist to secure storage.
  Future<void> _persistSession() async {
    try {
      final json = await _bridge.exportSession();
      if (json == null) return;
      await _tokenStore.saveSession(
        ownerUserId: await _ownerUserId(),
        region: ref.read(garminRegionProvider),
        sessionJson: json,
      );
    } catch (_) {
      // Non-fatal: user can still use the session this launch.
    }
  }

  /// Load saved credentials for secure form prefill.
  Future<GarminSavedCredentials?> loadSavedCredentials() async {
    return _tokenStore.loadCredentials(ownerUserId: await _ownerUserId());
  }

  Future<String> _ownerUserId() async {
    return ref.read(currentUserIdProvider)();
  }

  GarminConnected _restoredConnectedState(String ownerUserId) {
    final status = GarminSyncStatusStore(
      ref.read(sharedPreferencesProvider),
    ).read(ownerUserId);
    return GarminConnected(
      lastSyncAt: status?.lastSuccessAt,
      totalMetrics: status?.totalMetrics ?? 0,
    );
  }

  Future<GarminConnected> _restoredConnectedStateForCurrentOwner() async {
    return _restoredConnectedState(await _ownerUserId());
  }

  Future<GarminConnected> _recordSuccessfulSync({
    required DateTime attemptedAt,
    required int totalMetrics,
  }) async {
    final ownerUserId = await _ownerUserId();
    final completedAt = DateTime.now().toUtc();
    await GarminSyncStatusStore(ref.read(sharedPreferencesProvider)).write(
      ownerUserId: ownerUserId,
      lastAttemptAt: attemptedAt,
      lastSuccessAt: completedAt,
      totalMetrics: totalMetrics,
    );
    return GarminConnected(lastSyncAt: completedAt, totalMetrics: totalMetrics);
  }

  Future<void> _clearSyncStatus() async {
    await GarminSyncStatusStore(
      ref.read(sharedPreferencesProvider),
    ).clear(await _ownerUserId());
  }

  Future<bool> _recoverWithSavedCredentials({AppLogger? logger}) async {
    final credentials = await loadSavedCredentials();
    if (credentials == null) return false;
    logger?.i('HealthOS Garmin attempting secure credential session recovery');
    if (ref.read(garminRegionProvider) != credentials.region) {
      await ref.read(garminRegionProvider.notifier).set(credentials.region);
      _initialized = false;
      _initializedRegion = null;
    }
    _pendingCredentials = credentials;
    _pendingRememberPassword = true;
    try {
      await _ensureInit();
      final result = await _bridge.authenticate(
        credentials.email,
        credentials.password,
      );
      switch (result.type) {
        case GarminAuthResultType.authenticated:
          await _persistSession();
          await _commitCredentialPreference();
          state = await _restoredConnectedStateForCurrentOwner();
          logger?.i('HealthOS Garmin secure credential recovery succeeded');
          return true;
        case GarminAuthResultType.mfaRequired:
          state = const GarminPendingMfa();
          logger?.i('HealthOS Garmin recovery requires MFA');
          return false;
        case GarminAuthResultType.failed:
          _clearPendingCredentials();
          await _tokenStore.clearCredentials(ownerUserId: await _ownerUserId());
          state = const GarminError(
            GarminSyncIssue(
              code: 'credentials_invalid',
              severity: GarminSyncIssueSeverity.error,
              message: 'Saved Garmin credentials are no longer valid',
              action: GarminSyncIssueAction.reconnect,
            ),
          );
          logger?.w('HealthOS Garmin saved credentials are no longer valid');
          return false;
      }
    } catch (_) {
      _clearPendingCredentials();
      return false;
    }
  }

  Future<void> _commitCredentialPreference() async {
    final credentials = _pendingCredentials;
    final ownerUserId = await _ownerUserId();
    if (_pendingRememberPassword && credentials != null) {
      await _tokenStore.saveCredentials(
        ownerUserId: ownerUserId,
        credentials: credentials,
      );
    } else {
      await _tokenStore.clearCredentials(ownerUserId: ownerUserId);
    }
    _clearPendingCredentials();
  }

  void _clearPendingCredentials() {
    _pendingCredentials = null;
    _pendingRememberPassword = false;
  }
}
