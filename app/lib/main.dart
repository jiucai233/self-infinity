import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/app_state.dart';
import 'auth/auth_service.dart';
import 'auth/supabase_auth.dart';
import 'l10n/l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final locale = await LocaleController.load();
  AuthService auth = LocalAuth();
  if (kAccountsEnabled) {
    await Supabase.initialize(url: kSupabaseUrl, publishableKey: kSupabaseAnonKey);
    auth = SupabaseAuthService();
  }
  runApp(
    SelfInfinityApp(
      api: createApiFromEnvironment(auth: auth.enabled ? auth : null),
      appState: AppState(),
      auth: auth,
      locale: locale,
    ),
  );
}
