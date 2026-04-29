import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_errors.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _submitting = false;
  bool _obscurePassword = true;
  AuthErrorKind? _lastErrorKind;
  String? _lastErrorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _lastErrorKind = null;
      _lastErrorMessage = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(
            email: _emailController.text,
            password: _passwordController.text,
            deviceName: _suggestedDeviceName(),
          );
      // The router redirect will pick up the AuthLoggedIn transition and
      // bounce us to the original destination (or `/`).
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _lastErrorKind = e.kind;
        _lastErrorMessage = e.message;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _suggestedDeviceName() {
    if (kIsWeb) return 'Web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.android => 'Android',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => null,
    };
  }

  String _errorMessage(AppLocalizations l10n, AuthErrorKind kind) {
    return switch (kind) {
      AuthErrorKind.invalidCredentials => l10n.authLoginErrorInvalidCredentials,
      AuthErrorKind.network => l10n.authLoginErrorNetwork,
      AuthErrorKind.server => l10n.authLoginErrorServer,
      AuthErrorKind.unauthorized ||
      AuthErrorKind.badRequest ||
      AuthErrorKind.unknown => l10n.authLoginErrorGeneric,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authControllerProvider).valueOrNull;
    // Banner is purely informational — once the user types anything we
    // suppress it (cleared on submit) so the form doesn't keep nagging.
    final showExpiredBanner = _lastErrorKind == null &&
        authState is AuthLoggedOut &&
        authState.reason == LoggedOutReason.sessionExpired;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.s24,
                vertical: Spacing.s32,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.appTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Spacing.s8),
                    Text(
                      l10n.authLoginTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Spacing.s24),
                    if (showExpiredBanner)
                      _Banner.info(
                        message: l10n.authLoginNoticeSessionExpired,
                      ),
                    if (_lastErrorKind != null) ...[
                      const SizedBox(height: Spacing.s8),
                      _Banner.error(
                        message: _errorMessage(l10n, _lastErrorKind!),
                        details: _lastErrorMessage,
                      ),
                    ],
                    const SizedBox(height: Spacing.s16),
                    TextFormField(
                      key: const ValueKey('login.email'),
                      controller: _emailController,
                      autofocus: !kIsWeb,
                      enabled: !_submitting,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.authEmailLabel,
                      ),
                      validator: (value) =>
                          _validateEmail(value, l10n: l10n),
                      onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                    ),
                    const SizedBox(height: Spacing.s16),
                    TextFormField(
                      key: const ValueKey('login.password'),
                      controller: _passwordController,
                      enabled: !_submitting,
                      focusNode: _passwordFocus,
                      autofillHints: const [AutofillHints.password],
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: l10n.authPasswordLabel,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscurePassword
                              ? l10n.authPasswordShowTooltip
                              : l10n.authPasswordHideTooltip,
                          onPressed: _submitting
                              ? null
                              : () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                        ),
                      ),
                      validator: (value) =>
                          _validatePassword(value, l10n: l10n),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: Spacing.s24),
                    FilledButton(
                      key: const ValueKey('login.submit'),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.authLoginSubmit),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? _validateEmail(String? raw, {required AppLocalizations l10n}) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return l10n.authEmailErrorEmpty;
  // Tight enough to catch typos, loose enough not to reject legitimate
  // addresses (e.g. plus-tags). Backend is authoritative.
  if (!_emailPattern.hasMatch(value)) return l10n.authEmailErrorInvalid;
  return null;
}

String? _validatePassword(String? raw, {required AppLocalizations l10n}) {
  final value = raw ?? '';
  if (value.isEmpty) return l10n.authPasswordErrorEmpty;
  if (value.length < 8) return l10n.authPasswordErrorTooShort;
  return null;
}

final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

class _Banner extends StatelessWidget {
  const _Banner._({
    required this.message,
    required this.color,
    required this.iconColor,
    required this.icon,
    this.details,
  });

  factory _Banner.info({required String message}) {
    return _Banner._(
      message: message,
      icon: Icons.info_outline,
      color: const Color(0x1A1976D2),
      iconColor: const Color(0xFF1976D2),
    );
  }

  factory _Banner.error({required String message, String? details}) {
    return _Banner._(
      message: message,
      details: details,
      icon: Icons.error_outline,
      color: const Color(0x1AD32F2F),
      iconColor: const Color(0xFFD32F2F),
    );
  }

  final String message;
  final String? details;
  final Color color;
  final Color iconColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Spacing.s12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: Radii.brSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: Spacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: theme.textTheme.bodyMedium),
                if (details != null && details!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    details!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
