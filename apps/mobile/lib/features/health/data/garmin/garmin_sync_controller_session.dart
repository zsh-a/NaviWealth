part of 'garmin_sync_controller.dart';

extension _GarminSessionAuth on _GarminSession {
  Future<void> restore() => restoreFuture ??= queue.run(() async {
    if (!active) return;
    try {
      final stored = await guarded(
        tokenStore.loadSession(ownerUserId: owner, region: region),
      );
      final credentials = await guarded(
        tokenStore.loadCredentials(ownerUserId: owner),
      );
      if (stored == null &&
          (credentials == null || credentials.region != region)) {
        return;
      }
      state = const GarminRestoring();
      if (await ensureSession()) state = restoredState();
    } on _GarminCancelled {
      // An old owner/region must never publish into the replacement session.
    } on Object catch (error) {
      state = GarminError(GarminSyncIssue.fromLegacyMessage(error.toString()));
    }
  });

  Future<bool> ensureSession() async {
    checkActive();
    final stored = initialized
        ? null
        : await guarded(
            tokenStore.loadSession(ownerUserId: owner, region: region),
          );
    if (!initialized && stored == null) return recoverCredentials();
    final authState = initialized
        ? await guarded(bridge.authState())
        : await guarded(
            bridge.init(storedTokenJson: stored, isCn: region.isCn),
          );
    initialized = true;
    if (authState.canMakeRequests) {
      await persistSession();
      return true;
    }
    if (authState.needsMfa) {
      state = const GarminPendingMfa();
      return false;
    }
    final issue = garminRestoreAuthIssue(authState);
    await guarded(tokenStore.clearSession(ownerUserId: owner, region: region));
    initialized = false;
    if (await recoverCredentials()) return true;
    if (state is! GarminPendingMfa && state is! GarminError) {
      state = GarminError(issue);
    }
    return false;
  }

  Future<void> connect(
    String email,
    String password, {
    required bool rememberPassword,
  }) async {
    if (authenticating) return;
    authenticating = true;
    try {
      await cancel();
      await restore();
      await queue.run(() async {
        if (!active) return;
        try {
          state = GarminSyncing(startedAt: clock().toUtc(), phase: 'auth');
          pendingCredentials = GarminSavedCredentials(
            email: email,
            password: password,
            region: region,
          );
          this.rememberPassword = rememberPassword;
          await guarded(bridge.init(isCn: region.isCn));
          initialized = true;
          final result = await guarded(bridge.authenticate(email, password));
          await acceptAuth(result, newConnection: true);
        } on _GarminCancelled {
          // Cancelled by an owner/region transition.
        } on Object catch (error) {
          pendingCredentials = null;
          state = GarminError(
            GarminSyncIssue.fromLegacyMessage(error.toString()),
          );
        }
      });
    } finally {
      authenticating = false;
    }
  }

  Future<void> submitMfa(String code) async {
    if (authenticating || state is! GarminPendingMfa) return;
    authenticating = true;
    try {
      await queue.run(() async {
        if (!active) return;
        try {
          state = const GarminPendingMfa(submitting: true);
          final result = await guarded(bridge.submitMfa(code));
          await acceptAuth(result, newConnection: false);
        } on _GarminCancelled {
          // Cancelled by an owner/region transition.
        } on Object catch (error) {
          state = GarminError(
            GarminSyncIssue.fromLegacyMessage(error.toString()),
          );
        }
      });
    } finally {
      authenticating = false;
    }
  }

  Future<void> acceptAuth(
    GarminAuthResult result, {
    required bool newConnection,
  }) async {
    switch (result.type) {
      case GarminAuthResultType.authenticated:
        await persistSession();
        if (rememberPassword && pendingCredentials != null) {
          await guarded(
            tokenStore.saveCredentials(
              ownerUserId: owner,
              credentials: pendingCredentials!,
            ),
          );
        } else {
          await guarded(tokenStore.clearCredentials(ownerUserId: owner));
        }
        pendingCredentials = null;
        // A new account binding must not inherit historical completion markers.
        if (newConnection) await guarded(statusStore.clear(owner));
        state = restoredState();
      case GarminAuthResultType.mfaRequired:
        if (newConnection) await guarded(statusStore.clear(owner));
        state = const GarminPendingMfa();
      case GarminAuthResultType.failed:
        pendingCredentials = null;
        // A rejected login needs user intervention, not automatic password
        // retries every time the foreground timer wakes.
        state = const GarminError(
          GarminSyncIssue(
            code: 'credentials_invalid',
            severity: GarminSyncIssueSeverity.error,
            message: 'Garmin credentials were rejected',
            action: GarminSyncIssueAction.reconnect,
          ),
        );
    }
  }

  Future<bool> recoverCredentials() async {
    final credentials = await guarded(
      tokenStore.loadCredentials(ownerUserId: owner),
    );
    if (credentials == null || credentials.region != region) return false;
    pendingCredentials = credentials;
    rememberPassword = true;
    if (!initialized) {
      await guarded(bridge.init(isCn: region.isCn));
      initialized = true;
    }
    final result = await guarded(
      bridge.authenticate(credentials.email, credentials.password),
    );
    await acceptAuth(result, newConnection: false);
    return result.type == GarminAuthResultType.authenticated;
  }

  Future<void> persistSession() async {
    final json = await guarded(bridge.exportSession());
    if (json == null) return;
    await guarded(
      tokenStore.saveSession(
        ownerUserId: owner,
        region: region,
        sessionJson: json,
      ),
    );
  }

  GarminConnected restoredState() {
    final saved = status;
    return GarminConnected(
      lastSyncAt: saved?.lastSuccessAt,
      totalMetrics: saved?.totalMetrics ?? 0,
      lastAttemptAt: saved?.lastAttemptAt,
      lastErrorCode: saved?.errorCode,
      lastCheckedAt: saved?.lastCheckedAt,
      unchanged: saved?.unchanged ?? 0,
      partial: saved?.partial ?? false,
    );
  }

  Future<void> disconnect() async {
    await cancel();
    await queue.run(() async {
      if (!active) return;
      try {
        if (initialized) await guarded(bridge.logout());
        await guarded(tokenStore.clearAll(ownerUserId: owner));
        await guarded(statusStore.clear(owner));
        initialized = false;
        pendingCredentials = null;
        state = const GarminInitial();
      } on _GarminCancelled {
        // The queued replacement session owns further native work.
      } on Object catch (error) {
        state = GarminError(
          GarminSyncIssue.fromLegacyMessage(error.toString()),
        );
      }
    });
  }
}
