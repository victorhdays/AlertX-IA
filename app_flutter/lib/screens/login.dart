import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/repository.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.repository,
    this.enablePreview = false,
  });
  final ReportRepository repository;
  final bool enablePreview;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _obscure = true;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy || !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.signIn(_email.text, _password.text);
      TextInput.finishAutofillContext();
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is AppException
              ? e.message
              : 'No se pudo iniciar sesión. Intenta nuevamente.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 950;
        return Row(
          children: [
            if (wide)
              Expanded(
                child: Container(
                  color: forest,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(56),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Brand(light: true),
                          const Spacer(),
                          const Eyebrow(
                            'CADA REPORTE CUENTA',
                            color: Color(0xFFB5CBBF),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Un mejor camino\nempieza contigo.',
                            style: TextStyle(
                              fontSize: 52,
                              height: 1.08,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Reporta incidentes viales, comparte su ubicación\ny consulta su seguimiento desde un solo lugar.',
                            style: TextStyle(
                              color: Color(0xFFD1DED7),
                              fontSize: 17,
                              height: 1.65,
                            ),
                          ),
                          const SizedBox(height: 42),
                          const _RoadIllustration(),
                          const Spacer(),
                          const Row(
                            children: [
                              Icon(
                                Icons.lock_outline,
                                size: 16,
                                color: Color(0xFFB5CBBF),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tu información, bajo tu control.',
                                  style: TextStyle(color: Color(0xFFB5CBBF)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(wide ? 56 : 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: AutofillGroup(
                        child: Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!wide) ...[
                                const Brand(),
                                const SizedBox(height: 52),
                              ],
                              const Eyebrow('BIENVENIDO A ALERTX'),
                              const SizedBox(height: 16),
                              Text(
                                'Tu tranquilidad,\nen el camino.',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineLarge,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Inicia sesión para registrar y dar seguimiento a tus reportes.',
                                style: TextStyle(color: muted, height: 1.6),
                              ),
                              const SizedBox(height: 36),
                              TextFormField(
                                controller: _email,
                                enabled: !_busy,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [
                                  AutofillHints.username,
                                  AutofillHints.email,
                                ],
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'Correo electrónico',
                                  hintText: 'nombre@correo.com',
                                  prefixIcon: Icon(
                                    Icons.alternate_email,
                                    size: 20,
                                  ),
                                ),
                                validator: (value) =>
                                    RegExp(
                                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                    ).hasMatch(value?.trim() ?? '')
                                    ? null
                                    : 'Escribe un correo válido.',
                              ),
                              const SizedBox(height: 18),
                              TextFormField(
                                controller: _password,
                                enabled: !_busy,
                                obscureText: _obscure,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _login(),
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  prefixIcon: const Icon(
                                    Icons.lock_outline,
                                    size: 20,
                                  ),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure
                                        ? 'Mostrar contraseña'
                                        : 'Ocultar contraseña',
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                validator: (value) =>
                                    (value?.isNotEmpty ?? false)
                                    ? null
                                    : 'Escribe tu contraseña.',
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => showDialog<void>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Recupera tu acceso'),
                                      content: const Text(
                                        'Solicita al administrador de tu organización que restablezca tu acceso. Nunca compartas tu contraseña.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Entendido'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  child: const Text(
                                    '¿Necesitas ayuda para entrar?',
                                  ),
                                ),
                              ),
                              if (_error != null) ...[
                                ErrorNotice(_error!),
                                const SizedBox(height: 16),
                              ],
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _busy ? null : _login,
                                  child: _busy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text('Iniciar sesión'),
                                            SizedBox(width: 16),
                                            Icon(Icons.arrow_forward, size: 18),
                                          ],
                                        ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              const Text(
                                'Acceso para cuentas registradas por tu organización.',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                              if (widget.enablePreview) ...[
                                const SizedBox(height: 16),
                                TextButton.icon(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => Dashboard(
                                        repository: PreviewRepository(),
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.visibility_outlined),
                                  label: const Text('Explorar vista previa'),
                                ),
                              ],
                              const SizedBox(height: 40),
                              const Divider(),
                              const SizedBox(height: 16),
                              const Text(
                                'Ante una emergencia, llama al 911. AlertX no sustituye a los servicios de emergencia.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _RoadIllustration extends StatelessWidget {
  const _RoadIllustration();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 140,
    width: 380,
    child: CustomPaint(painter: _RoadPainter()),
  );
}

class _RoadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * .8)
      ..cubicTo(
        size.width * .4,
        size.height * .8,
        size.width * .4,
        size.height * .2,
        size.width,
        size.height * .2,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF41665B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 50,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF9CB4A5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      Offset(size.width * .52, size.height * .47),
      17,
      Paint()..color = accent,
    );
    canvas.drawCircle(
      Offset(size.width * .52, size.height * .47),
      5,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(size.width * .93, size.height * .205),
      5,
      Paint()..color = const Color(0xFFD2E3D7),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
