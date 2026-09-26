import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/repository.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'report_form.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.repository});
  final ReportRepository repository;
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int _page = 0, _generation = 0;
  bool _loading = true, _moreLoading = false, _hasMore = false;
  String? _error, _moreError;
  List<Report> _reports = [];
  ReportStats _stats = const ReportStats();
  DateTime? _updated;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _moreError = null;
      _moreLoading = false;
    });
    try {
      final results = await Future.wait<Object>([
        widget.repository.reports(),
        widget.repository.statistics(),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _reports = results[0] as List<Report>;
        _stats = results[1] as ReportStats;
        _hasMore = _reports.length == 20;
        _updated = DateTime.now();
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = e is AppException
              ? e.message
              : 'No se pudieron cargar tus reportes.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_moreLoading || _loading) return;
    final generation = _generation;
    setState(() {
      _moreLoading = true;
      _moreError = null;
    });
    try {
      final next = await widget.repository.reports(offset: _reports.length);
      if (mounted && generation == _generation) {
        setState(() {
          final known = _reports.map((r) => r.id).toSet();
          _reports.addAll(next.where((r) => !known.contains(r.id)));
          _hasMore = next.length == 20;
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () => _moreError = e is AppException
              ? e.message
              : 'No se pudieron cargar más reportes.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _moreLoading = false);
      }
    }
  }

  Future<void> _newReport() async {
    final report = await showDialog<Report>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReportForm(repository: widget.repository),
    );
    if (!mounted || report == null) return;
    showMessage(context, 'Reporte ${report.shortId} guardado correctamente.');
    await _refresh();
  }

  Future<void> _logout() async {
    if (widget.repository.preview) {
      Navigator.of(context).pop();
      return;
    }
    try {
      await widget.repository.signOut();
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'No se pudo cerrar la sesión. Intenta nuevamente.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      return Scaffold(
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _page,
                onDestinationSelected: (page) => setState(() => _page = page),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.space_dashboard_outlined),
                    selectedIcon: Icon(Icons.space_dashboard),
                    label: 'Inicio',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    label: 'Mis reportes',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.help_outline),
                    label: 'Ayuda',
                  ),
                ],
              ),
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide) _sidebar(),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 36 : 20,
                        vertical: 18,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(bottom: BorderSide(color: line)),
                      ),
                      child: Row(
                        children: [
                          if (!wide)
                            const Brand()
                          else ...[
                            const Icon(
                              Icons.location_on_outlined,
                              size: 17,
                              color: muted,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Poza Rica, Veracruz',
                              style: TextStyle(fontSize: 13, color: muted),
                            ),
                          ],
                          const Spacer(),
                          if (wide)
                            Text(
                              widget.repository.email,
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          const SizedBox(width: 12),
                          Tooltip(
                            message: widget.repository.email,
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFFECF0E9),
                              child: Text(
                                widget.repository.email.isEmpty
                                    ? 'A'
                                    : widget.repository.email[0].toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: forest,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          if (!wide)
                            IconButton(
                              tooltip: 'Cerrar sesión',
                              onPressed: _logout,
                              icon: const Icon(Icons.logout, size: 20),
                            ),
                        ],
                      ),
                    ),
                    if (widget.repository.preview)
                      Container(
                        width: double.infinity,
                        color: const Color(0xFFFFECCC),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: const Text(
                          'VISTA PREVIA · Datos de ejemplo. El envío de reportes está deshabilitado.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF76510B),
                          ),
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refresh,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.all(wide ? 36 : 20),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1200),
                              child: _page == 2
                                  ? const HelpContent()
                                  : _content(wide),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _sidebar() => Container(
    width: 238,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(left: 12), child: Brand()),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Text(
            'MOVILIDAD SEGURA',
            style: TextStyle(fontSize: 9, letterSpacing: 2.5, color: muted),
          ),
        ),
        const SizedBox(height: 52),
        const Padding(
          padding: EdgeInsets.only(left: 12, bottom: 12),
          child: Eyebrow('MI ESPACIO'),
        ),
        _nav(0, Icons.grid_view_rounded, 'Resumen'),
        _nav(1, Icons.receipt_long_outlined, 'Mis reportes'),
        _nav(2, Icons.help_outline, 'Centro de ayuda'),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: canvas,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, color: forest, size: 24),
              SizedBox(height: 12),
              Text(
                'Reportar hace la diferencia',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text(
                'Comparte información clara y ayuda a cuidar el camino.',
                style: TextStyle(fontSize: 12, height: 1.6, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout, size: 18),
          label: Text(
            widget.repository.preview
                ? 'Salir de la vista previa'
                : 'Cerrar sesión',
          ),
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'AlertX  /  v1.0',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ),
      ],
    ),
  );

  Widget _nav(int index, IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: _page == index ? const Color(0xFFEBF0E9) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selected: _page == index,
        selectedColor: forest,
        leading: Icon(icon, size: 20),
        title: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        onTap: () => setState(() => _page = index),
      ),
    ),
  );

  Widget _content(bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(_page == 0 ? 'TU ESPACIO VIAL' : 'HISTORIAL PERSONAL'),
                const SizedBox(height: 10),
                Text(
                  _page == 0 ? 'Cada camino, más seguro.' : 'Mis reportes',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _page == 0
                      ? 'Un lugar para reportar, consultar y dar seguimiento.'
                      : 'Consulta la información y el estado de tus incidentes.',
                  style: const TextStyle(color: muted),
                ),
              ],
            ),
          ),
          if (wide) ...[
            const SizedBox(width: 20),
            FilledButton.icon(
              onPressed: _newReport,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nuevo reporte'),
            ),
          ],
        ],
      ),
      const SizedBox(height: 28),
      if (_page == 0) ...[
        _hero(wide),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, box) {
            final count = box.maxWidth >= 650 ? 4 : 2;
            final width = (box.maxWidth - (count - 1) * 12) / count;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _stat(
                  'Reportes enviados',
                  _stats.total,
                  Icons.outbox_outlined,
                  width,
                  forest,
                ),
                _stat(
                  'Recibidos',
                  _stats.received,
                  Icons.inbox_outlined,
                  width,
                  const Color(0xFF5A6B8D),
                ),
                _stat(
                  'En revisión',
                  _stats.reviewing,
                  Icons.schedule_outlined,
                  width,
                  const Color(0xFF916315),
                ),
                _stat('Cerrados', _stats.closed, Icons.task_alt, width, forest),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
      ] else if (!wide) ...[
        FilledButton.icon(
          onPressed: _newReport,
          icon: const Icon(Icons.add),
          label: const Text('Nuevo reporte'),
        ),
        const SizedBox(height: 20),
      ],
      Surface(
        padding: EdgeInsets.all(wide ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _page == 0 ? 'Actividad reciente' : 'Todos tus reportes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Actualizar reportes',
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.refresh, size: 21),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _updated == null
                  ? 'El estado de tus reportes aparecerá aquí.'
                  : 'Actualizado a las ${DateFormat('HH:mm').format(_updated!)}',
              style: const TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const LoadingReports()
            else if (_error != null)
              ErrorNotice(_error!, onRetry: _refresh)
            else if (_reports.isEmpty)
              _empty()
            else ...[
              ...(_page == 0 ? _reports.take(4) : _reports).map(
                (report) => _reportRow(report, wide),
              ),
              if (_page == 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _page = 1),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('Ver mis reportes'),
                  ),
                ),
              if (_page == 1 && _moreError != null)
                ErrorNotice(_moreError!, onRetry: _loadMore),
              if (_page == 1 && _hasMore)
                Center(
                  child: TextButton(
                    onPressed: _moreLoading ? null : _loadMore,
                    child: Text(
                      _moreLoading ? 'Cargando…' : 'Cargar más reportes',
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 24,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 14, color: muted),
              SizedBox(width: 6),
              Text(
                'Tus reportes son privados.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
          TextButton(
            onPressed: () => setState(() => _page = 2),
            child: const Text(
              'Cómo funciona AlertX',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _hero(bool wide) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(wide ? 32 : 24),
    decoration: BoxDecoration(
      color: forest,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow(
                'ESTAMOS EN EL MISMO CAMINO',
                color: Color(0xFFB9D1C3),
              ),
              const SizedBox(height: 16),
              const Text(
                '¿Viste un incidente vial?',
                style: TextStyle(
                  fontSize: 26,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.6,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Comparte qué ocurrió y dónde.\nPuedes consultar tu reporte en cualquier momento.',
                style: TextStyle(
                  color: Color(0xFFD7E3DB),
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF0F4E8),
                  foregroundColor: forest,
                ),
                onPressed: _newReport,
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('Registrar un incidente'),
              ),
              const SizedBox(height: 16),
              const Text(
                'En una emergencia, llama al 911.',
                style: TextStyle(fontSize: 12, color: Color(0xFFD7E3DB)),
              ),
            ],
          ),
        ),
        if (wide) ...[
          const SizedBox(width: 28),
          Container(
            width: 138,
            height: 138,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF527366)),
            ),
            child: const Icon(
              Icons.add_road_rounded,
              size: 68,
              color: Color(0xFFBCD0B4),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _stat(
    String title,
    int value,
    IconData icon,
    double width,
    Color color,
  ) => SizedBox(
    width: width,
    child: Surface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 18),
          if (_loading)
            const Skeleton(width: 48, height: 32)
          else
            Text(
              _error != null ? '—' : '$value',
              style: const TextStyle(
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w600,
                letterSpacing: -1,
              ),
            ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 12, color: muted)),
        ],
      ),
    ),
  );

  Widget _empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36),
    child: Center(
      child: Column(
        children: [
          const Icon(Icons.route_outlined, size: 42, color: forest),
          const SizedBox(height: 18),
          const Text(
            'Tu historial empieza aquí',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cuando registres un incidente, podrás consultarlo en este espacio.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _newReport,
            icon: const Icon(Icons.add),
            label: const Text('Crear mi primer reporte'),
          ),
        ],
      ),
    ),
  );

  Widget _reportRow(Report report, bool wide) => Column(
    children: [
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showReportDetail(context, report),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: canvas,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  report.type == 'colision'
                      ? Icons.car_crash_outlined
                      : Icons.traffic_outlined,
                  size: 20,
                  color: forest,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${DateFormat('d MMM · HH:mm', 'es').format(report.createdAt)}  ·  ${report.shortId}',
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                    if (!wide) ...[
                      const SizedBox(height: 8),
                      StatusBadge(report),
                    ],
                  ],
                ),
              ),
              if (wide) ...[StatusBadge(report), const SizedBox(width: 24)],
              const Icon(Icons.chevron_right, color: muted, size: 19),
            ],
          ),
        ),
      ),
      const Divider(height: 1),
    ],
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.report, {super.key});
  final Report report;
  @override
  Widget build(BuildContext context) {
    final color = switch (report.status) {
      'en_revision' => const Color(0xFF896012),
      'cerrado' => forest,
      _ => const Color(0xFF456081),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 5, color: color),
          const SizedBox(width: 6),
          Text(
            report.statusLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showReportDetail(
  BuildContext context,
  Report report,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(report.title),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusBadge(report),
            const SizedBox(height: 20),
            const Eyebrow('FOLIO'),
            const SizedBox(height: 4),
            SelectableText(report.id),
            const SizedBox(height: 16),
            Text(
              DateFormat('d MMMM yyyy · HH:mm', 'es').format(report.createdAt),
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 20),
            Text(report.description),
            const SizedBox(height: 20),
            const Eyebrow('UBICACIÓN REGISTRADA'),
            const SizedBox(height: 6),
            SelectableText(
              '${report.latitude.toStringAsFixed(6)}, ${report.longitude.toStringAsFixed(6)}',
            ),
            const SizedBox(height: 20),
            const Text(
              'El registro confirma la recepción de la información. No implica el envío de servicios de emergencia.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
    ],
  ),
);

class HelpContent extends StatelessWidget {
  const HelpContent({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Eyebrow('CENTRO DE AYUDA'),
      const SizedBox(height: 12),
      Text(
        'Información para tu camino.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 24),
      Surface(
        color: const Color(0xFFFFF2EC),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.phone_in_talk_outlined, color: accent),
            const SizedBox(height: 12),
            const Text(
              '¿Necesitas ayuda de emergencia?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Llama al 911. AlertX registra incidentes y no está conectado a un servicio de despacho de unidades.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: accent),
              onPressed: () async {
                try {
                  final opened = await launchUrl(
                    Uri(scheme: 'tel', path: '911'),
                  );
                  if (!opened && context.mounted) {
                    showMessage(context, 'Marca 911 desde tu teléfono.');
                  }
                } catch (_) {
                  if (context.mounted) {
                    showMessage(context, 'Marca 911 desde tu teléfono.');
                  }
                }
              },
              icon: const Icon(Icons.phone_outlined),
              label: const Text('Llamar al 911'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      ...const [
        (
          '01',
          'Registra lo que observaste',
          'Selecciona el tipo de incidente y describe lo ocurrido. Evita incluir nombres, placas u otros datos personales innecesarios.',
        ),
        (
          '02',
          'Confirma la ubicación',
          'Comparte el GPS de tu dispositivo o escribe las coordenadas del incidente. Revisa que correspondan al lugar correcto antes de enviar.',
        ),
        (
          '03',
          'Consulta tu historial',
          'Recibido significa que el reporte se guardó. En revisión y Cerrado reflejan actualizaciones realizadas por tu organización.',
        ),
        (
          '04',
          'Tu información es privada',
          'Solo puedes consultar los reportes de tu cuenta. El administrador autorizado de tu organización gestiona su seguimiento. Solicita a tu organización la eliminación de tu cuenta y sus reportes.',
        ),
      ].map(
        (item) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Surface(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.$1,
                  style: const TextStyle(
                    fontSize: 20,
                    color: forest,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$2,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(item.$3, style: const TextStyle(color: muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
