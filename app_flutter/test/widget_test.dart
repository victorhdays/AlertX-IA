import 'dart:async';
import 'package:app_flutter/data/repository.dart';
import 'package:app_flutter/main.dart';
import 'package:app_flutter/screens/report_form.dart';
import 'package:app_flutter/ui/components.dart';
import 'package:app_flutter/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestRepository extends UnconfiguredRepository {
  bool signedIn = false;
  int loginCalls = 0, fetchCalls = 0;
  Completer<List<Report>>? pending;
  bool failFetch = false, failSubmit = false;
  final submissions = <Map<String, dynamic>>[];
  @override
  bool get authenticated => signedIn;
  @override
  String get email => 'test@example.com';
  @override
  Future<void> signIn(String email, String password) async {
    loginCalls++;
    if (password == 'incorrect') throw const AppException('Credenciales incorrectas.');
    signedIn = true;
    notifyListeners();
  }
  @override
  Future<void> signOut() async { signedIn = false; notifyListeners(); }
  @override
  Future<List<Report>> reports({int offset = 0}) async {
    fetchCalls++;
    if (failFetch) throw const AppException('Sin conexión.');
    return pending == null ? [] : pending!.future;
  }
  @override
  Future<Report> submit(Map<String, dynamic> payload) async {
    submissions.add(Map.of(payload));
    if (failSubmit) throw const AppException('Tiempo de espera agotado.');
    return Report(id: '12345678-1234-1234-1234-123456789012', createdAt: DateTime.now(), description: payload['descripcion'], type: payload['tipo'], status: 'recibido', latitude: payload['latitud'], longitude: payload['longitud']);
  }
}

void main() {
  testWidgets('invalid login never authenticates and auth errors are visible', (tester) async {
    final repo = TestRepository();
    await tester.pumpWidget(AlertXApp(repository: repo));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(repo.loginCalls, 0);
    expect(find.text('Escribe un correo válido.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'test@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'incorrect');
    await tester.ensureVisible(find.text('Iniciar sesión'));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Credenciales incorrectas.'), findsOneWidget);
    expect(repo.authenticated, false);
  });

  testWidgets('skeleton becomes an honest empty state', (tester) async {
    final repo = TestRepository()..signedIn = true..pending = Completer<List<Report>>();
    await tester.pumpWidget(AlertXApp(repository: repo));
    expect(find.byType(LoadingReports), findsOneWidget);
    repo.pending!.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(LoadingReports), findsNothing);
    expect(find.text('Tu historial empieza aquí'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed load supports retry', (tester) async {
    final repo = TestRepository()..signedIn = true..failFetch = true;
    await tester.pumpWidget(AlertXApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.text('Sin conexión.'), findsOneWidget);
    repo.failFetch = false;
    await tester.ensureVisible(find.text('Reintentar'));
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(repo.fetchCalls, 2);
    expect(find.text('Tu historial empieza aquí'), findsOneWidget);
  });

  for (final size in [const Size(320, 700), const Size(390, 844), const Size(1440, 900), const Size(1024, 600)]) {
    testWidgets('login and dashboard adapt to $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = TestRepository();
      await tester.pumpWidget(AlertXApp(repository: repo));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      repo.signedIn = true;
      repo.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('report retry keeps its identity and payload after a timeout', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = TestRepository()..failSubmit = true;
    await tester.pumpWidget(MaterialApp(theme: alertTheme(), home: Scaffold(body: ReportForm(repository: repo))));
    await tester.enterText(find.byType(TextFormField).at(0), 'Vehículo detenido en el cruce principal');
    await tester.enterText(find.byType(TextFormField).at(1), '20.5333');
    await tester.enterText(find.byType(TextFormField).at(2), '-97.4595');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.ensureVisible(find.text('Enviar reporte'));
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    expect(find.text('Tiempo de espera agotado.'), findsOneWidget);
    await tester.ensureVisible(find.text('Reintentar envío'));
    await tester.tap(find.text('Reintentar envío'));
    await tester.pumpAndSettle();
    expect(repo.submissions.length, 2);
    expect(repo.submissions[0], repo.submissions[1]);
    expect(repo.submissions[0].containsKey('usuario_id'), false);
  });

  testWidgets('preview cannot submit incidents', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReportForm(repository: PreviewRepository()))));
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Enviar reporte'));
    expect(button.onPressed, isNull);
  });

  test('configuration rejects insecure external endpoints', () {
    expect(validEndpoint('http://api.example.com'), false);
    expect(validEndpoint('https://api.example.com'), true);
    expect(validEndpoint('http://localhost:8000'), true);
    expect(validEndpoint('https://user:password@api.example.com'), false);
  });
}
