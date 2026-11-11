import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/supabase_service_repository.dart';
import '../domain/service.dart';

final serviceRepositoryProvider = Provider<ServiceRepository>(
  (ref) => SupabaseServiceRepository(ref.watch(supabaseClientProvider)),
);

final serviceCategoriesProvider = FutureProvider<List<ServiceCategory>>(
  (ref) => ref.watch(serviceRepositoryProvider).categories(),
);

/// Catálogo completo (incluye inactivos) para la pantalla de administración.
final servicesProvider = FutureProvider<List<Service>>(
  (ref) => ref.watch(serviceRepositoryProvider).services(),
);

/// Solo servicios activos, para seleccionar al crear turnos.
final activeServicesProvider = Provider<AsyncValue<List<Service>>>(
  (ref) => ref.watch(servicesProvider).whenData((l) => l.where((s) => s.isActive).toList()),
);

final combosProvider = FutureProvider<List<Combo>>(
  (ref) => ref.watch(serviceRepositoryProvider).combos(),
);

final priceHistoryProvider = FutureProvider.autoDispose.family<List<PriceChange>, String>(
  (ref, id) => ref.watch(serviceRepositoryProvider).priceHistory(id),
);
