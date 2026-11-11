import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../payments/domain/payment.dart';
import '../data/supabase_client_repository.dart';
import '../domain/entities/client.dart';
import '../domain/repositories/client_repository.dart';

final clientRepositoryProvider = Provider<ClientRepository>((ref) {
  final user = ref.watch(sessionUserProvider);
  return SupabaseClientRepository(ref.watch(supabaseClientProvider), centerId: user.centerId);
});

/// Texto de búsqueda actual de la lista de clientes.
final clientSearchProvider = StateProvider.autoDispose<String>((ref) => '');

/// Lista paginada con scroll infinito.
class ClientListController extends AutoDisposeAsyncNotifier<List<Client>> {
  static const _pageSize = 30;
  int _page = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  bool get hasMore => _hasMore;

  @override
  Future<List<Client>> build() async {
    final query = ref.watch(clientSearchProvider);
    // Debounce: si el usuario sigue escribiendo, el provider se reconstruye y esta ejecución se descarta.
    var cancelled = false;
    ref.onDispose(() => cancelled = true);
    if (query.isNotEmpty) await Future<void>.delayed(const Duration(milliseconds: 300));
    if (cancelled) return const [];

    _page = 0;
    final items = await ref.read(clientRepositoryProvider).search(query: query, pageSize: _pageSize);
    _hasMore = items.length == _pageSize;
    return items;
  }

  Future<void> loadMore() async {
    if (!_hasMore || _loadingMore || state.isLoading) return;
    _loadingMore = true;
    try {
      final next = await ref
          .read(clientRepositoryProvider)
          .search(query: ref.read(clientSearchProvider), page: _page + 1, pageSize: _pageSize);
      _page++;
      _hasMore = next.length == _pageSize;
      state = AsyncData([...state.valueOrNull ?? [], ...next]);
    } finally {
      _loadingMore = false;
    }
  }
}

final clientListProvider =
    AsyncNotifierProvider.autoDispose<ClientListController, List<Client>>(ClientListController.new);

final clientProvider = FutureProvider.autoDispose.family<Client, String>(
  (ref, id) => ref.watch(clientRepositoryProvider).getById(id),
);

final clientStatsProvider = FutureProvider.autoDispose.family<ClientStats, String>(
  (ref, id) => ref.watch(clientRepositoryProvider).stats(id),
);

final clinicalRecordsProvider = FutureProvider.autoDispose.family<List<ClinicalRecord>, String>(
  (ref, id) => ref.watch(clientRepositoryProvider).clinicalRecords(id),
);

final clientPaymentsProvider = FutureProvider.autoDispose.family<List<Payment>, String>(
  (ref, id) => ref.watch(clientRepositoryProvider).payments(id),
);

/// Invalida todo lo relacionado a un cliente tras una mutación.
void refreshClient(WidgetRef ref, String id) {
  ref.invalidate(clientProvider(id));
  ref.invalidate(clientStatsProvider(id));
  ref.invalidate(clientListProvider);
}
