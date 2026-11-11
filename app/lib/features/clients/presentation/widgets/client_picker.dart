import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../domain/entities/client.dart';
import '../clients_providers.dart';

/// Hoja modal para buscar y elegir un cliente (o crear uno nuevo).
Future<Client?> showClientPicker(BuildContext context) => showModalBottomSheet<Client>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FractionallySizedBox(heightFactor: 0.9, child: _ClientPicker()),
    );

class _ClientPicker extends ConsumerStatefulWidget {
  const _ClientPicker();

  @override
  ConsumerState<_ClientPicker> createState() => _ClientPickerState();
}

class _ClientPickerState extends ConsumerState<_ClientPicker> {
  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientListProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Buscar por nombre, DNI o teléfono',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (v) => ref.read(clientSearchProvider.notifier).state = v,
          ),
        ),
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1_rounded)),
          title: const Text('Nuevo cliente'),
          onTap: () async {
            final created = await context.push<Client>('/clientes/nuevo');
            if (created != null && context.mounted) Navigator.pop(context, created);
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: AsyncValueView(
            value: clients,
            data: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.search_off_rounded, title: 'Sin resultados')
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      return ListTile(
                        leading: InitialsAvatar(initials: Fmt.initials(c.fullName)),
                        title: Text(c.fullName),
                        subtitle: Text([c.dni, c.whatsapp ?? c.phone].whereType<String>().join(' · ')),
                        trailing: c.hasHealthAlerts
                            ? const Tooltip(
                                message: 'Tiene alergias o contraindicaciones',
                                child: Icon(Icons.health_and_safety_outlined, color: Colors.orange),
                              )
                            : null,
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
