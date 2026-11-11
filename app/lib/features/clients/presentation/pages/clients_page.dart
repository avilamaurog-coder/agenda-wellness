import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../auth/presentation/auth_providers.dart';
import '../clients_providers.dart';

class ClientsPage extends ConsumerStatefulWidget {
  const ClientsPage({super.key});

  @override
  ConsumerState<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends ConsumerState<ClientsPage> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        ref.read(clientListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionUserProvider);
    final clients = ref.watch(clientListProvider);
    final query = ref.watch(clientSearchProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchBar(
              hintText: 'Buscar por nombre, DNI, teléfono o email',
              leading: const Icon(Icons.search_rounded),
              elevation: const WidgetStatePropertyAll<double>(0),
              onChanged: (v) => ref.read(clientSearchProvider.notifier).state = v,
            ),
          ),
        ),
      ),
      floatingActionButton: user.canManageClients
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/clientes/nuevo'),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Cliente'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(clientListProvider.future),
        child: AsyncValueView(
          value: clients,
          onRetry: () => ref.invalidate(clientListProvider),
          data: (list) {
            if (list.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: query.isEmpty ? Icons.people_outline : Icons.search_off_rounded,
                  title: query.isEmpty ? 'Todavía no hay clientes' : 'Sin resultados para "$query"',
                  message: query.isEmpty && user.canManageClients ? 'Cargá tu primer cliente para empezar a agendar.' : null,
                ),
              ]);
            }
            final hasMore = ref.read(clientListProvider.notifier).hasMore;
            return ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: list.length + (hasMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                if (i >= list.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final c = list[i];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: InitialsAvatar(initials: Fmt.initials(c.fullName)),
                    title: Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [if (c.dni != null) 'DNI ${c.dni}', c.whatsapp ?? c.phone].whereType<String>().join(' · '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (c.birthdayThisWeek)
                          const Tooltip(message: 'Cumple esta semana', child: Text('🎂', style: TextStyle(fontSize: 18))),
                        if (c.hasHealthAlerts)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Tooltip(
                              message: 'Alergias o contraindicaciones',
                              child: Icon(Icons.health_and_safety_outlined, color: Colors.orange),
                            ),
                          ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                    onTap: () => context.push('/clientes/${c.id}'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
