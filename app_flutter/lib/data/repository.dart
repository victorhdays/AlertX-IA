import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const incidentTypes = {
  'colision': 'Colisión vehicular',
  'obstruccion': 'Obstrucción en la vía',
  'riesgo_vial': 'Riesgo vial',
  'otro': 'Otro incidente',
};

class AppException implements Exception {
  const AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Report {
  const Report({
    required this.id,
    required this.createdAt,
    required this.description,
    required this.type,
    required this.status,
    required this.latitude,
    required this.longitude,
  });
  final String id, description, type, status;
  final DateTime createdAt;
  final double latitude, longitude;
  String get title => incidentTypes[type] ?? 'Incidente vial';
  String get shortId =>
      id.substring(0, id.length < 8 ? id.length : 8).toUpperCase();
  String get statusLabel => switch (status) {
    'en_revision' => 'En revisión',
    'cerrado' => 'Cerrado',
    _ => 'Recibido',
  };
  factory Report.fromJson(Map<String, dynamic> json) => Report(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    description: json['descripcion'] as String,
    type: json['tipo'] as String,
    status: json['estado'] as String,
    latitude: (json['latitud'] as num).toDouble(),
    longitude: (json['longitud'] as num).toDouble(),
  );
}

class ReportStats {
  const ReportStats({
    this.total = 0,
    this.received = 0,
    this.reviewing = 0,
    this.closed = 0,
  });
  final int total, received, reviewing, closed;
  factory ReportStats.fromJson(Map<String, dynamic> json) => ReportStats(
    total: json['total'] as int,
    received: json['recibidos'] as int,
    reviewing: json['en_revision'] as int,
    closed: json['cerrados'] as int,
  );
}

abstract class ReportRepository extends ChangeNotifier {
  bool get authenticated;
  bool get preview => false;
  String get email;
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<List<Report>> reports({int offset = 0});
  Future<ReportStats> statistics();
  Future<Report> submit(Map<String, dynamic> payload);
}

class SupabaseReportRepository extends ReportRepository {
  SupabaseReportRepository(this.auth, this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client() {
    _subscription = auth.onAuthStateChange.listen(
      (_) => notifyListeners(),
      onError: (_) {
        notifyListeners();
      },
    );
  }
  final GoTrueClient auth;
  final String baseUrl;
  final http.Client _client;
  late final StreamSubscription<AuthState> _subscription;
  @override
  bool get authenticated => auth.currentSession != null;
  @override
  String get email => auth.currentUser?.email ?? '';
  @override
  Future<void> signIn(String email, String password) async {
    try {
      await auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw AppException(
        e.statusCode == '429'
            ? 'Demasiados intentos. Espera un momento antes de continuar.'
            : 'No pudimos iniciar sesión. Revisa tus datos y confirma tu correo.',
      );
    } catch (_) {
      throw const AppException(
        'No se pudo conectar. Revisa tu conexión e intenta de nuevo.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    // Always remove the local session, even if the network is unavailable.
    await auth.signOut(scope: SignOutScope.local);
  }

  Future<dynamic> _request(String path, {Map<String, dynamic>? payload}) async {
    try {
      var session = auth.currentSession;
      if (session?.isExpired ?? false) {
        session = (await auth.refreshSession()).session;
      }
      if (session == null) {
        throw const AppException('Inicia sesión para continuar.');
      }
      final headers = {
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      };
      final uri = Uri.parse('${baseUrl.replaceFirst(RegExp(r"/+$"), "")}$path');
      final response =
          await (payload == null
                  ? _client.get(uri, headers: headers)
                  : _client.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(payload),
                    ))
              .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401) {
        await signOut();
        throw const AppException('Tu sesión expiró. Vuelve a iniciar sesión.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AppException(switch (response.statusCode) {
          429 =>
            'Has enviado varios reportes. Espera un minuto e intenta otra vez.',
          422 => 'Revisa la descripción y las coordenadas del incidente.',
          409 => 'Este envío ya existe con otros datos. Consulta tu historial.',
          _ => 'No pudimos completar la solicitud. Intenta nuevamente.',
        });
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw const AppException(
        'La conexión tardó demasiado. Puedes reintentar el mismo envío sin duplicarlo.',
      );
    } on AuthException {
      throw const AppException(
        'No se pudo renovar tu sesión. Vuelve a iniciar sesión.',
      );
    } catch (_) {
      throw const AppException(
        'No se pudo conectar con AlertX. Revisa tu conexión.',
      );
    }
  }

  @override
  Future<List<Report>> reports({int offset = 0}) async =>
      (await _request('/reportes?limit=20&offset=$offset') as List)
          .map((r) => Report.fromJson(r as Map<String, dynamic>))
          .toList();
  @override
  Future<ReportStats> statistics() async =>
      ReportStats.fromJson(await _request('/estadisticas'));
  @override
  Future<Report> submit(Map<String, dynamic> payload) async =>
      Report.fromJson(await _request('/reportes', payload: payload));
  @override
  void dispose() {
    _subscription.cancel();
    _client.close();
    super.dispose();
  }
}

class UnconfiguredRepository extends ReportRepository {
  @override
  bool get authenticated => false;
  @override
  String get email => '';
  @override
  Future<void> signIn(String email, String password) async =>
      throw const AppException(
        'El servicio aún no está disponible. Intenta más tarde.',
      );
  @override
  Future<void> signOut() async {}
  @override
  Future<List<Report>> reports({int offset = 0}) async => [];
  @override
  Future<ReportStats> statistics() async => const ReportStats();
  @override
  Future<Report> submit(Map<String, dynamic> payload) async =>
      throw const AppException('Servicio no disponible.');
}

/// Explicit, read-only preview. Never sends or stores a real incident.
class PreviewRepository extends UnconfiguredRepository {
  @override
  bool get preview => true;
  @override
  bool get authenticated => true;
  @override
  String get email => 'Vista previa';
  @override
  Future<List<Report>> reports({int offset = 0}) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (offset > 0) return [];
    return [
      Report(
        id: 'AX260914-001',
        createdAt: DateTime.now().subtract(const Duration(minutes: 24)),
        description:
            'Vehículo detenido junto al carril derecho, a la altura del cruce principal.',
        type: 'obstruccion',
        status: 'recibido',
        latitude: 20.5333,
        longitude: -97.4595,
      ),
      Report(
        id: 'AX260913-002',
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        description:
            'Colisión entre dos vehículos. Se reporta afectación a la circulación.',
        type: 'colision',
        status: 'en_revision',
        latitude: 20.5298,
        longitude: -97.4660,
      ),
      Report(
        id: 'AX260912-003',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        description: 'Señalización caída junto al acceso a la avenida.',
        type: 'riesgo_vial',
        status: 'cerrado',
        latitude: 20.5347,
        longitude: -97.4598,
      ),
    ];
  }

  @override
  Future<ReportStats> statistics() async =>
      const ReportStats(total: 3, received: 1, reviewing: 1, closed: 1);
}
