import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/entities/appointment.dart';
import '../pages/appointment_detail_sheet.dart';

/// Chip de estado con color + ícono + texto (accesible sin depender solo del color).
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false});
  final AppointmentStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = status.color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: dense ? 12 : 14, color: c),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: dense ? 10 : 12),
          ),
        ],
      ),
    );
  }
}

/// Fila de turno para listas (dashboard, historial del cliente).
class AppointmentTile extends StatelessWidget {
  const AppointmentTile({super.key, required this.appointment, this.showDate = false, this.showClient = true});
  final Appointment appointment;
  final bool showDate;
  final bool showClient;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final t = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showAppointmentDetail(context, a.id),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: a.status.color),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (showDate)
                      Text(Fmt.shortDate(a.startsAt), style: t.textTheme.labelSmall),
                    Text(Fmt.time(a.startsAt), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(Fmt.duration(a.duration.inMinutes),
                        style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(showClient ? a.clientName : a.serviceName,
                          style: t.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        showClient ? '${a.serviceName} · ${a.therapistName}' : a.therapistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(child: StatusChip(a.status, dense: true)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
