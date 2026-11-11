import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/widgets/common_widgets.dart';
import '../../domain/entities/client.dart';
import '../clients_providers.dart';

Future<bool?> showClinicalRecordSheet(BuildContext context, {required String clientId, String? appointmentId}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _ClinicalRecordForm(clientId: clientId, appointmentId: appointmentId),
      ),
    );

class _ClinicalRecordForm extends ConsumerStatefulWidget {
  const _ClinicalRecordForm({required this.clientId, this.appointmentId});
  final String clientId;
  final String? appointmentId;

  @override
  ConsumerState<_ClinicalRecordForm> createState() => _ClinicalRecordFormState();
}

class _ClinicalRecordFormState extends ConsumerState<_ClinicalRecordForm> {
  final _evaluation = TextEditingController();
  final _goals = TextEditingController();
  final _evolution = TextEditingController();
  final _observations = TextEditingController();
  double? _pain;
  final _photos = <Uint8List>[];
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_evaluation, _goals, _evolution, _observations]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 82);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _photos.add(bytes));
  }

  Future<void> _save() async {
    final empty = [_evaluation, _goals, _evolution, _observations].every((c) => c.text.trim().isEmpty);
    if (empty && _photos.isEmpty) {
      context.showSnack('Completá al menos un campo', error: true);
      return;
    }
    setState(() => _saving = true);
    String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await ref.read(clientRepositoryProvider).addClinicalRecord(
            ClinicalRecord(
              clientId: widget.clientId,
              appointmentId: widget.appointmentId,
              recordDate: DateTime.now(),
              evaluation: v(_evaluation),
              treatmentGoals: v(_goals),
              evolution: v(_evolution),
              observations: v(_observations),
              painScale: _pain?.round(),
            ),
            photos: _photos,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: const Text('Nueva evaluación'),
        actions: [TextButton(onPressed: _saving ? null : _save, child: const Text('Guardar'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          TextField(controller: _evaluation, maxLines: 3, decoration: const InputDecoration(labelText: 'Evaluación')),
          gap,
          TextField(controller: _goals, maxLines: 2, decoration: const InputDecoration(labelText: 'Objetivos del tratamiento')),
          gap,
          TextField(controller: _evolution, maxLines: 3, decoration: const InputDecoration(labelText: 'Evolución')),
          gap,
          TextField(controller: _observations, maxLines: 2, decoration: const InputDecoration(labelText: 'Observaciones')),
          const SectionTitle('Escala de dolor'),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _pain ?? 0,
                  max: 10,
                  divisions: 10,
                  label: _pain == null ? 'Sin registrar' : '${_pain!.round()}',
                  onChanged: (x) => setState(() => _pain = x),
                ),
              ),
              Text(_pain == null ? '—' : '${_pain!.round()}/10'),
            ],
          ),
          const SectionTitle('Fotografías de seguimiento'),
          Text(
            'Se guardan en almacenamiento privado; solo las ven administradores y profesionales del cliente.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _photos.length; i++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_photos[i], width: 90, height: 90, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton.filledTonal(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _photos.removeAt(i)),
                      ),
                    ),
                  ],
                ),
              _AddPhotoButton(icon: Icons.photo_camera_outlined, label: 'Cámara', onTap: () => _addPhoto(ImageSource.camera)),
              _AddPhotoButton(icon: Icons.photo_library_outlined, label: 'Galería', onTap: () => _addPhoto(ImageSource.gallery)),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar evaluación')),
        ],
      ),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  const _AddPhotoButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(icon), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 12))],
        ),
      ),
    );
  }
}
