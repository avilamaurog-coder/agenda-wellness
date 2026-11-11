import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/formatters.dart';
import '../data/supabase_dashboard_repository.dart';
import '../domain/dashboard_summary.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => SupabaseDashboardRepository(ref.watch(supabaseClientProvider)),
);

enum DashboardPeriod {
  week('7 días'),
  month('Este mes'),
  quarter('90 días'),
  year('Este año');

  const DashboardPeriod(this.label);
  final String label;

  (DateTime, DateTime) get range {
    final today = DateTime.now().dateOnly;
    return switch (this) {
      week => (today.subtract(const Duration(days: 6)), today),
      month => (DateTime(today.year, today.month), today),
      quarter => (today.subtract(const Duration(days: 89)), today),
      year => (DateTime(today.year), today),
    };
  }
}

final dashboardPeriodProvider = StateProvider<DashboardPeriod>((ref) => DashboardPeriod.month);

final dashboardProvider = FutureProvider.autoDispose<DashboardSummary>((ref) {
  final (from, to) = ref.watch(dashboardPeriodProvider).range;
  return ref.watch(dashboardRepositoryProvider).summary(from: from, to: to);
});
