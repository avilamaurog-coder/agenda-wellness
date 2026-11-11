import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/supabase_center_repository.dart';
import '../domain/center.dart';

/// Historial de copias de seguridad en la nube y backup manual (solo administradores).
class BackupsPage extends ConsumerStatefulWidget {
  const BackupsPage({super.key});

  @override
  ConsumerState<BackupsPage> createState() => _BackupsPageState();
}

class _BackupsPageState extends ConsumerState<BackupsPage> {
  bool _running = false;

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      await ref.read(centerRepositoryProvider).runBackupNow();
      if (mounted) context.showSnack('Backup creado y subido a tu nube');
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      ref.invalidate(backupsProvider);
      if (mounted) setState(() => _running = false);
    }
  }

  String _size(int? b) {
    if (b == null) return '';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final backups = ref.watch(backupsProvider);
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Copias de seguridad')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(backupsProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud_done_outlined, color: t.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('Backup en tu nube', style: t.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Todas las noches a las 03:00 se exportan clientes, turnos, pagos, fichas, servicios y '
                      'configuración a un archivo comprimido y cifrado en tu Google Drive (o OneDrive). '
                      'Se conservan los últimos 30 días.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _running ? null : _run,
                      icon: _running
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.backup_rounded),
                      label: Text(_running ? 'Creando backup…' : 'Hacer backup ahora'),
                    ),
                  ],
                ),
              ),
            ),
            const SectionTitle('Historial'),
            AsyncValueView<List<BackupRecord>>(
              value: backups,
              onRetry: () => ref.invalidate(backupsProvider),
              loading: const SizedBox(height: 200, child: LoadingList(items: 3)),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Todavía no se realizó ningún backup.', textAlign: TextAlign.center),
                    )
                  : Column(
                      children: [
                        for (final b in list)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(
                                switch (b.status) {
                                  'success' => Icons.check_circle_rounded,
                                  'failed' => Icons.error_rounded,
                                  _ => Icons.hourglass_top_rounded,
                                },
                                color: switch (b.status) {
                                  'success' => AppColors.completed,
                                  'failed' => AppColors.cancelled,
                                  _ => AppColors.pending,
                                },
                              ),
                              title: Text('${Fmt.shortDate(b.startedAt)} · ${Fmt.time(b.startedAt)}'),
                              subtitle: Text(
                                b.status == 'failed'
                                    ? (b.error ?? 'Error')
                                    : [
                                        b.providerLabel,
                                        if (b.sizeBytes != null) _size(b.sizeBytes),
                                        if (b.encrypted) '🔒 cifrado',
                                        b.trigger == 'manual' ? 'manual' : 'automático',
                                      ].join(' · '),
                                maxLines: 3,
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
  }
}
