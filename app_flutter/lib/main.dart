import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/repository.dart';
import 'screens/dashboard.dart';
import 'screens/login.dart';
import 'ui/theme.dart';

bool validEndpoint(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      (uri.scheme == 'https' ||
          (uri.scheme == 'http' &&
              const ['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host)));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const publicKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  const apiUrl = String.fromEnvironment('API_BASE_URL');
  ReportRepository repository = UnconfiguredRepository();
  if (validEndpoint(supabaseUrl) &&
      validEndpoint(apiUrl) &&
      publicKey.isNotEmpty &&
      !publicKey.startsWith('sb_secret_')) {
    try {
      await Supabase.initialize(url: supabaseUrl, publishableKey: publicKey);
      repository = SupabaseReportRepository(
        Supabase.instance.client.auth,
        apiUrl,
      );
    } catch (_) {
      // Keep a usable error screen if local session storage cannot initialize.
    }
  }
  runApp(AlertXApp(repository: repository));
}

class AlertXApp extends StatelessWidget {
  const AlertXApp({
    super.key,
    required this.repository,
    this.enablePreview = const bool.fromEnvironment('DEMO_MODE'),
  });
  final ReportRepository repository;
  final bool enablePreview;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'AlertX · Movilidad segura',
    theme: alertTheme(),
    locale: const Locale('es', 'MX'),
    supportedLocales: const [Locale('es', 'MX')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: ListenableBuilder(
      listenable: repository,
      builder: (context, _) => repository.authenticated
          ? Dashboard(key: ValueKey(repository.email), repository: repository)
          : LoginScreen(repository: repository, enablePreview: enablePreview),
    ),
  );
}
