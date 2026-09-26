import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../data/repository.dart';
import '../ui/components.dart';
import '../ui/theme.dart';

class ReportForm extends StatefulWidget {
  const ReportForm({super.key, required this.repository});
  final ReportRepository repository;
  @override
  State<ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<ReportForm> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController(),
      _latitude = TextEditingController(),
      _longitude = TextEditingController();
  String _type = 'colision';
  String? _error;
  double? _accuracy;
  bool _busy = false, _locating = false, _confirmed = false;
  Map<String, dynamic>? _pending;
  @override
  void dispose() {
    _description.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const AppException(
          'Activa la ubicación del dispositivo o escribe las coordenadas.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const AppException(
          'No tenemos permiso para acceder a tu ubicación. Puedes escribir las coordenadas o habilitar el permiso en ajustes.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude.text = position.latitude.toStringAsFixed(6);
        _longitude.text = position.longitude.toStringAsFixed(6);
        _accuracy = position.accuracy;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AppException
              ? e.message
              : 'No se pudo obtener la ubicación. Intenta de nuevo o escribe las coordenadas.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String? _coordinate(String? value, double min, double max) {
    final number = double.tryParse((value ?? '').replaceAll(',', '.'));
    return number == null || !number.isFinite || number < min || number > max
        ? 'Usa un valor entre $min y $max.'
        : null;
  }

  Future<void> _submit() async {
    if (_busy || _locating || !_form.currentState!.validate()) return;
    if (!_confirmed) {
      setState(
        () => _error = 'Confirma que revisaste la información antes de enviar.',
      );
      return;
    }
    // Freeze both the key and payload after the first attempt. A timeout may have
    // occurred after a successful insert: retry exactly the same operation.
    _pending ??= {
      'request_id': const Uuid().v4(),
      'tipo': _type,
      'descripcion': _description.text.trim(),
      'latitud': double.parse(_latitude.text.replaceAll(',', '.')),
      'longitud': double.parse(_longitude.text.replaceAll(',', '.')),
      'precision_metros': _accuracy,
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await widget.repository.submit(_pending!);
      if (mounted) Navigator.of(context).pop(report);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AppException
              ? e.message
              : 'No se pudo confirmar el envío. Reintenta sin cerrar este formulario.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = !_busy && _pending == null;
    return PopScope(
      canPop: !_busy && !_locating,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Eyebrow('NUEVO REPORTE')),
                      IconButton(
                        tooltip: 'Cerrar formulario',
                        onPressed: _busy || _locating
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(
                    'Cuéntanos qué ocurrió.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Registra el incidente desde un lugar seguro. Si necesitas atención de emergencia, llama al 911.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 24),
                  if (widget.repository.preview) ...[
                    const ErrorNotice(
                      'Vista previa: puedes explorar el formulario, pero no se enviarán reportes.',
                    ),
                    const SizedBox(height: 20),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de incidente',
                    ),
                    items: incidentTypes.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: editable
                        ? (value) => setState(() => _type = value!)
                        : null,
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _description,
                    enabled: editable,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: '¿Qué observaste?',
                      alignLabelWithHint: true,
                      hintText:
                          'Describe el incidente y alguna referencia del lugar.',
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 15
                        ? 'Describe el incidente con al menos 15 caracteres.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  const Eyebrow('UBICACIÓN DEL INCIDENTE'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: editable && !_locating ? _locate : null,
                    icon: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location, size: 18),
                    label: Text(
                      _locating
                          ? 'Obteniendo ubicación…'
                          : 'Usar mi ubicación actual',
                    ),
                  ),
                  if (_accuracy != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Precisión estimada: ${_accuracy!.round()} m. Revisa las coordenadas.',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, box) {
                      final fields = [
                        TextFormField(
                          controller: _latitude,
                          enabled: editable && !_locating,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitud',
                            hintText: '20.533300',
                          ),
                          onChanged: (_) => setState(() => _accuracy = null),
                          validator: (v) => _coordinate(v, -90, 90),
                        ),
                        TextFormField(
                          controller: _longitude,
                          enabled: editable && !_locating,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitud',
                            hintText: '-97.459500',
                          ),
                          onChanged: (_) => setState(() => _accuracy = null),
                          validator: (v) => _coordinate(v, -180, 180),
                        ),
                      ];
                      return box.maxWidth < 340
                          ? Column(
                              children: [
                                fields[0],
                                const SizedBox(height: 16),
                                fields[1],
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: fields[0]),
                                const SizedBox(width: 16),
                                Expanded(child: fields[1]),
                              ],
                            );
                    },
                  ),
                  const SizedBox(height: 18),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _confirmed,
                    onChanged: editable
                        ? (value) => setState(() => _confirmed = value ?? false)
                        : null,
                    title: const Text(
                      'Revisé la ubicación y la información de mi reporte.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null) ...[
                    ErrorNotice(_error!),
                    const SizedBox(height: 16),
                  ],
                  if (_pending != null && !_busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Conservamos este envío para evitar duplicados. Reintenta con los mismos datos o consulta tu historial antes de crear otro reporte.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy || _locating || widget.repository.preview
                          ? null
                          : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined, size: 18),
                      label: Text(
                        _busy
                            ? 'Guardando reporte…'
                            : _pending == null
                            ? 'Enviar reporte'
                            : 'Reintentar envío',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Guardar un reporte no solicita una ambulancia ni confirma atención de emergencias.',
                    style: TextStyle(fontSize: 11, color: muted),
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
