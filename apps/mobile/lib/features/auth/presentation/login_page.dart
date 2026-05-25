import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:forui/forui.dart';

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
  _AuthMode _mode = _AuthMode.signIn;
  bool _submitting = false;
  final bool _obscurePassword = true;
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
      final controller = ref.read(authControllerProvider.notifier);
      if (_mode == _AuthMode.signIn) {
        await controller.login(
          email: _emailController.text,
          password: _passwordController.text,
          deviceName: _suggestedDeviceName(),
        );
      } else {
        await controller.register(
          email: _emailController.text,
          password: _passwordController.text,
          deviceName: _suggestedDeviceName(),
        );
      }
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

  void _toggleMode() {
    if (_submitting) return;
    setState(() {
      _mode = switch (_mode) {
        _AuthMode.signIn => _AuthMode.register,
        _AuthMode.register => _AuthMode.signIn,
      };
      _lastErrorKind = null;
      _lastErrorMessage = null;
    });
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
      AuthErrorKind.accountExists => l10n.authRegisterErrorAccountExists,
      AuthErrorKind.unauthorized ||
      AuthErrorKind.badRequest ||
      AuthErrorKind.unknown => l10n.authLoginErrorGeneric,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authControllerProvider).value;
    // Banner is purely informational — once the user types anything we
    // suppress it (cleared on submit) so the form doesn't keep nagging.
    final showExpiredBanner =
        _lastErrorKind == null &&
        authState is AuthLoggedOut &&
        authState.reason == LoggedOutReason.sessionExpired;
    return FScaffold(
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 32,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SvgPicture.asset(
                              'assets/svg/logo.svg',
                              width: 80,
                              height: 80,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.appTitle,
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _mode == _AuthMode.signIn
                                  ? l10n.authLoginTitle
                                  : l10n.authRegisterTitle,
                              style: context.theme.typography.md,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            if (showExpiredBanner)
                              _Banner(
                                kind: _BannerKind.info,
                                message: l10n.authLoginNoticeSessionExpired,
                              ),
                            if (_lastErrorKind != null) ...[
                              const SizedBox(height: 8),
                              _Banner(
                                kind: _BannerKind.error,
                                message: _errorMessage(l10n, _lastErrorKind!),
                                details: _lastErrorMessage,
                              ),
                            ],
                            const SizedBox(height: 16),
                            FTextFormField(
                              key: const ValueKey('login.email'),
                              control: FTextFieldControl.managed(
                                controller: _emailController,
                              ),
                              label: Text(l10n.authEmailLabel),
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofocus: !kIsWeb,
                              enabled: !_submitting,
                              autofillHints: const [
                                AutofillHints.username,
                                AutofillHints.email,
                              ],
                              validator: (value) =>
                                  _validateEmail(value, l10n: l10n),
                              onSubmit: (_) => _passwordFocus.requestFocus(),
                            ),
                            const SizedBox(height: 16),
                            FTextFormField(
                              key: const ValueKey('login.password'),
                              control: FTextFieldControl.managed(
                                controller: _passwordController,
                              ),
                              label: Text(l10n.authPasswordLabel),
                              focusNode: _passwordFocus,
                              textInputAction: TextInputAction.done,
                              obscureText: _obscurePassword,
                              enabled: !_submitting,
                              autofillHints: [
                                _mode == _AuthMode.signIn
                                    ? AutofillHints.password
                                    : AutofillHints.newPassword,
                              ],
                              validator: (value) =>
                                  _validatePassword(value, l10n: l10n),
                              onSubmit: (_) => _submit(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              AppFormActionBar(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FButton(
                          key: const ValueKey('login.submit'),
                          variant: FButtonVariant.primary,
                          onPress: _submitting ? null : _submit,
                          child: Text(
                            _submitting
                                ? ''
                                : _mode == _AuthMode.signIn
                                ? l10n.authLoginSubmit
                                : l10n.authRegisterSubmit,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FButton(
                          key: const ValueKey('login.toggleMode'),
                          variant: FButtonVariant.ghost,
                          onPress: _submitting ? null : _toggleMode,
                          child: Text(
                            _mode == _AuthMode.signIn
                                ? l10n.authRegisterSwitch
                                : l10n.authLoginSwitch,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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

enum _BannerKind { info, error }

enum _AuthMode { signIn, register }

class _Banner extends StatelessWidget {
  const _Banner({required this.kind, required this.message, this.details});

  final _BannerKind kind;
  final String message;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final semantic = SemanticColors.of(context);
    final (background, foreground, icon) = switch (kind) {
      _BannerKind.info => (
        semantic.infoContainer,
        semantic.info,
        FLucideIcons.info,
      ),
      _BannerKind.error => (
        semantic.dangerContainer,
        semantic.danger,
        FLucideIcons.circleAlert,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: context.theme.typography.sm),
                if (details != null && details!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    details!,
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
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
