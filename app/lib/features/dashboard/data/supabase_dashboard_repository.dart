import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';
import '../domain/dashboard_summary.dart';

class SupabaseDashboardRepository implements DashboardRepository {
  SupabaseDashboardRepository(this._db);
  final SupabaseClient _db;

  String? _d(DateTime? d) => d?.toIso8601String().substring(0, 10);

  @override
  Future<DashboardSummary> summary({DateTime? from, DateTime? to}) async {
    try {
      final json = await _db.rpc<Map<String, dynamic>>('dashboard_summary', params: {
        'p_from': _d(from),
        'p_to': _d(to),
      });
      return DashboardSummary.fromJson(json);
    } catch (e) {
      throw Failure.from(e);
    }
  }
}
