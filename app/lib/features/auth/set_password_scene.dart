import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_service.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';

/// Back from a password-reset link (`AuthService.recovering`): the account is
/// signed in, and a new password is set before the app opens.
class SetPasswordScene extends StatefulWidget {
  const SetPasswordScene({super.key});

  @override
  State<SetPasswordScene> createState() => _SetPasswordSceneState();
}

class _SetPasswordSceneState extends State<SetPasswordScene> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = context.read<AuthService>();
    final problem = AuthService.validate(auth.email ?? 'x@x', _password.text, newPassword: true);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await auth.updatePassword(_password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final auth = context.watch<AuthService>();
    return Scaffold(
      key: const Key('set-password'),
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.l10n.setNewPassword, style: theme.headlineMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    context.l10n.setNewPasswordBlurb,
                    style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                  if (auth.email case final email?) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(email, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary)),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    key: const Key('new-password'),
                    controller: _password,
                    obscureText: !_show,
                    autofocus: true,
                    autofillHints: const [AutofillHints.newPassword],
                    enabled: !_busy,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      hintText: context.l10n.passwordWithMin(AuthService.minPasswordLength),
                      suffixIcon: IconButton(
                        tooltip: _show ? context.l10n.hidePassword : context.l10n.showPassword,
                        icon: Icon(
                          _show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _show = !_show),
                      ),
                    ),
                  ),
                  if (_error case final e?) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      e,
                      key: const Key('set-password-error'),
                      style: theme.bodySmall?.copyWith(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    key: const Key('save-password'),
                    onPressed: _busy ? null : _save,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: Text(context.l10n.saveNewPassword),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
