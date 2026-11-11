import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/widgets/common_widgets.dart';
import '../../../center/data/supabase_center_repository.dart';
import '../../domain/entities/client.dart';
import '../clients_providers.dart';

/// Estado de vinculación con Telegram y acciones para invitar al cliente.
///
/// Flujo: el staff envía el enlace `t.me/<bot>?start=<código>` (por WhatsApp o copiándolo);
/// el cliente toca "Iniciar" en Telegram y queda vinculado. Desde ahí recibe los
/// recordatorios con botones para confirmar, reprogramar o cancelar.
class TelegramLinkCard extends ConsumerWidget {
  const TelegramLinkCard({super.key, required this.client, required this.canManage});
  final Client client;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final center = ref.watch(centerProvider).valueOrNull;
    final t = Theme.of(context);
    final c = client;

    if (c.telegramLinked) {
      return Card(
        child: ListTile(
          leading: const CircleAvatar(backgroundColor: Color(0xFF229ED9), child: Icon(Icons.send, color: Colors.white, size: 20)),
          title: const Text('Vinculado'),
          subtitle: Text(c.telegramUsername != null
              ? '@${c.telegramUsername} · recibe recordatorios y confirma desde el chat'
              : 'Recibe recordatorios y confirma desde el chat'),
          trailing: canManage
              ? PopupMenuButton<String>(
                  itemBuilder: (_) => const [PopupMenuItem(value: 'unlink', child: Text('Desvincular'))],
                  onSelected: (_) async {
                    if (!await context.confirm('Desvincular Telegram', 'El cliente dejará de recibir recordatorios por Telegram.',
                        ok: 'Desvincular', destructive: true)) {
                      return;
                    }
                    try {
                      await ref.read(clientRepositoryProvider).unlinkTelegram(c.id!);
                      refreshClient(ref, c.id!);
                    } catch (e) {
                      if (context.mounted) context.showError(e);
                    }
                  },
                )
              : null,
        ),
      );
    }

    final link = c.telegramLinkCode == null ? null : center?.telegramLinkFor(c.telegramLinkCode!);
    if (center != null && !center.telegramConfigured) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.send_outlined),
          title: Text('Telegram no configurado'),
          subtitle: Text('Un administrador debe cargar el usuario del bot en Más › Datos del centro.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.send_outlined, color: Color(0xFF229ED9)),
                const SizedBox(width: 8),
                Expanded(child: Text('Sin vincular', style: t.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Enviá el enlace al cliente: al abrirlo en Telegram queda vinculado y puede confirmar sus turnos con un toque.'),
            if (link != null && canManage) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if ((c.whatsapp ?? c.phone) != null)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                      icon: const Icon(Icons.chat_rounded, size: 18),
                      label: const Text('Enviar por WhatsApp'),
                      onPressed: () {
                        final phone = (c.whatsapp ?? c.phone)!.replaceAll(RegExp(r'\D'), '');
                        final msg = 'Hola ${c.firstName}! 🌿 Para recibir los recordatorios de tus turnos en '
                            '${center?.name ?? 'el centro'} y confirmarlos con un toque, abrí este enlace en Telegram: $link';
                        launchUrl(Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(msg)}'),
                            mode: LaunchMode.externalApplication);
                      },
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copiar enlace'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: link));
                      if (context.mounted) context.showSnack('Enlace copiado');
                    },
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        await ref.read(clientRepositoryProvider).regenerateTelegramCode(c.id!);
                        refreshClient(ref, c.id!);
                        if (context.mounted) context.showSnack('Se generó un enlace nuevo; el anterior ya no funciona');
                      } catch (e) {
                        if (context.mounted) context.showError(e);
                      }
                    },
                    child: const Text('Nuevo enlace'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
