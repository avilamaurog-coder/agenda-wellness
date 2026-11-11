import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/appointment.dart';

/// Definición de una columna de la grilla: un profesional (vista diaria)
/// o un día (vista semanal).
class TimelineColumn {
  const TimelineColumn({
    required this.title,
    required this.date,
    required this.appointments,
    this.subtitle,
    this.therapistId,
    this.color,
    this.highlight = false,
  });

  final String title;
  final String? subtitle;
  final DateTime date;
  final String? therapistId; // null → al soltar se conserva el profesional del turno
  final List<Appointment> appointments;
  final Color? color;
  final bool highlight;
}

typedef MoveCallback = Future<void> Function(Appointment appt, DateTime newStart, String? therapistId);

/// Grilla horaria con arrastrar y soltar.
///
/// * Mantener presionado un turno → se levanta; soltar en otra franja/columna → se reprograma.
/// * Tocar un espacio libre → crea un turno en ese horario.
/// * El horario se ajusta a bloques de [snapMinutes].
class TimelineGrid extends StatefulWidget {
  const TimelineGrid({
    super.key,
    required this.columns,
    required this.onTapAppointment,
    this.onMove,
    this.onTapEmpty,
    this.startHour = 8,
    this.endHour = 22,
    this.snapMinutes = 15,
    this.pixelsPerMinute = 1.5,
    this.minColumnWidth = 150,
  });

  final List<TimelineColumn> columns;
  final void Function(Appointment) onTapAppointment;
  final MoveCallback? onMove;
  final void Function(DateTime start, String? therapistId)? onTapEmpty;
  final int startHour;
  final int endHour;
  final int snapMinutes;
  final double pixelsPerMinute;
  final double minColumnWidth;

  @override
  State<TimelineGrid> createState() => _TimelineGridState();
}

class _TimelineGridState extends State<TimelineGrid> {
  static const _gutter = 52.0;
  static const _headerHeight = 52.0;
  late final ScrollController _vertical;
  Timer? _clock;

  double get _totalHeight => (widget.endHour - widget.startHour) * 60 * widget.pixelsPerMinute;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final minutesFromStart = ((now.hour - widget.startHour) * 60 + now.minute - 60).clamp(0, 24 * 60);
    _vertical = ScrollController(initialScrollOffset: minutesFromStart * widget.pixelsPerMinute);
    // Redibuja la línea de "ahora" cada minuto
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = math.max(1, widget.columns.length);
        final colWidth = math.max(widget.minColumnWidth, (constraints.maxWidth - _gutter) / n);
        final totalWidth = _gutter + colWidth * n;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(totalWidth, constraints.maxWidth),
            height: constraints.maxHeight,
            child: Column(
              children: [
                SizedBox(
                  height: _headerHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: _gutter),
                      for (final c in widget.columns) SizedBox(width: colWidth, child: _ColumnHeader(column: c)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _vertical,
                    child: SizedBox(
                      height: _totalHeight + 16,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _HourGutter(startHour: widget.startHour, endHour: widget.endHour, ppm: widget.pixelsPerMinute),
                          for (final c in widget.columns)
                            SizedBox(
                              width: colWidth,
                              height: _totalHeight,
                              child: _DayColumn(
                                column: c,
                                startHour: widget.startHour,
                                endHour: widget.endHour,
                                ppm: widget.pixelsPerMinute,
                                snap: widget.snapMinutes,
                                onTapAppointment: widget.onTapAppointment,
                                onMove: widget.onMove,
                                onTapEmpty: widget.onTapEmpty,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.column});
  final TimelineColumn column;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: t.colorScheme.outlineVariant.withValues(alpha: 0.5))),
        color: column.highlight ? t.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
      ),
      child: Row(
        children: [
          if (column.color != null) ...[
            CircleAvatar(radius: 5, backgroundColor: column.color),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(column.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                if (column.subtitle != null)
                  Text(column.subtitle!,
                      style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HourGutter extends StatelessWidget {
  const _HourGutter({required this.startHour, required this.endHour, required this.ppm});
  final int startHour;
  final int endHour;
  final double ppm;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return SizedBox(
      width: _TimelineGridState._gutter,
      height: (endHour - startHour) * 60 * ppm,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var h = startHour; h <= endHour; h++)
            Positioned(
              top: (h - startHour) * 60 * ppm - 7,
              right: 8,
              child: Text('${h.toString().padLeft(2, '0')}:00', style: style),
            ),
        ],
      ),
    );
  }
}

class _DayColumn extends StatefulWidget {
  const _DayColumn({
    required this.column,
    required this.startHour,
    required this.endHour,
    required this.ppm,
    required this.snap,
    required this.onTapAppointment,
    this.onMove,
    this.onTapEmpty,
  });

  final TimelineColumn column;
  final int startHour;
  final int endHour;
  final double ppm;
  final int snap;
  final void Function(Appointment) onTapAppointment;
  final MoveCallback? onMove;
  final void Function(DateTime, String?)? onTapEmpty;

  @override
  State<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<_DayColumn> {
  final _key = GlobalKey();
  DateTime? _hover; // franja resaltada durante el arrastre
  Duration _hoverDuration = Duration.zero;

  DateTime _timeAt(double dy) {
    final raw = (dy / widget.ppm).clamp(0, (widget.endHour - widget.startHour) * 60 - widget.snap).toDouble();
    final snapped = (raw / widget.snap).round() * widget.snap;
    final d = widget.column.date;
    return DateTime(d.year, d.month, d.day, widget.startHour).add(Duration(minutes: snapped));
  }

  double _top(DateTime t) => ((t.hour - widget.startHour) * 60 + t.minute) * widget.ppm;

  Offset? _local(Offset global) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = widget.column;
    final now = DateTime.now();
    final isToday = c.date.isSameDay(now);
    final hours = widget.endHour - widget.startHour;

    return DragTarget<Appointment>(
      onWillAcceptWithDetails: (d) => widget.onMove != null && d.data.status.isActive,
      onMove: (d) {
        final local = _local(d.offset);
        if (local == null) return;
        final time = _timeAt(local.dy);
        if (time != _hover) {
          HapticFeedback.selectionClick();
          setState(() {
            _hover = time;
            _hoverDuration = d.data.duration;
          });
        }
      },
      onLeave: (_) => setState(() => _hover = null),
      onAcceptWithDetails: (d) {
        final local = _local(d.offset);
        setState(() => _hover = null);
        if (local == null) return;
        widget.onMove?.call(d.data, _timeAt(local.dy), c.therapistId);
      },
      builder: (context, candidate, rejected) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: widget.onTapEmpty == null
              ? null
              : (details) => widget.onTapEmpty!(_timeAt(details.localPosition.dy), c.therapistId),
          child: Container(
            key: _key,
            decoration: BoxDecoration(
              color: candidate.isNotEmpty ? t.colorScheme.primary.withValues(alpha: 0.04) : null,
              border: Border(left: BorderSide(color: t.colorScheme.outlineVariant.withValues(alpha: 0.5))),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Líneas de hora y media hora
                for (var i = 0; i <= hours * 2; i++)
                  Positioned(
                    top: i * 30 * widget.ppm,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 1,
                      color: t.colorScheme.outlineVariant.withValues(alpha: i.isEven ? 0.45 : 0.18),
                    ),
                  ),

                // Fantasma de destino durante el arrastre
                if (_hover != null)
                  Positioned(
                    top: _top(_hover!),
                    left: 4,
                    right: 4,
                    height: _hoverDuration.inMinutes * widget.ppm,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.colorScheme.primary, width: 2),
                        color: t.colorScheme.primary.withValues(alpha: 0.08),
                      ),
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.all(6),
                      child: Text(Fmt.time(_hover!),
                          style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w800)),
                    ),
                  ),

                // Turnos
                for (final a in c.appointments)
                  Positioned(
                    top: _top(a.startsAt),
                    left: 4,
                    right: 4,
                    height: math.max(28, a.duration.inMinutes * widget.ppm - 2),
                    child: _DraggableAppointment(
                      appointment: a,
                      canDrag: widget.onMove != null && a.status.isActive,
                      onTap: () => widget.onTapAppointment(a),
                    ),
                  ),

                // Línea de hora actual
                if (isToday && now.hour >= widget.startHour && now.hour < widget.endHour)
                  Positioned(
                    top: _top(now) - 1,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: AppColors.terracotta, shape: BoxShape.circle),
                          ),
                          Expanded(child: Container(height: 2, color: AppColors.terracotta)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DraggableAppointment extends StatelessWidget {
  const _DraggableAppointment({required this.appointment, required this.canDrag, required this.onTap});
  final Appointment appointment;
  final bool canDrag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final card = AppointmentBlock(appointment: appointment, onTap: onTap);
    if (!canDrag) return card;

    return LayoutBuilder(
      builder: (context, box) {
        final feedback = Material(
          color: Colors.transparent,
          child: SizedBox(
            width: box.maxWidth,
            height: box.maxHeight,
            child: Transform.scale(
              scale: 1.03,
              child: AppointmentBlock(appointment: appointment, elevated: true),
            ),
          ),
        );
        final ghost = Opacity(opacity: 0.3, child: card);

        // Con mouse (web/escritorio) se arrastra directo; en táctil, manteniendo presionado
        // para no interferir con el scroll de la grilla.
        if (_usesPointer) {
          return MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Draggable<Appointment>(data: appointment, feedback: feedback, childWhenDragging: ghost, child: card),
          );
        }
        return LongPressDraggable<Appointment>(
          data: appointment,
          hapticFeedbackOnStart: true,
          delay: const Duration(milliseconds: 350),
          feedback: feedback,
          childWhenDragging: ghost,
          child: card,
        );
      },
    );
  }

  static bool get _usesPointer =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
}

/// Bloque visual del turno dentro de la grilla.
class AppointmentBlock extends StatelessWidget {
  const AppointmentBlock({super.key, required this.appointment, this.onTap, this.elevated = false});
  final Appointment appointment;
  final VoidCallback? onTap;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final statusColor = a.status.color;
    final bg = Color.alphaBlend(a.accent.withValues(alpha: dark ? 0.28 : 0.20), t.colorScheme.surface);
    final faded = a.status == AppointmentStatus.cancelled || a.status == AppointmentStatus.noShow;

    return Material(
      color: bg,
      elevation: elevated ? 8 : 0,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: statusColor, width: 4))),
          padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
          child: LayoutBuilder(
            builder: (context, c) {
              final compact = c.maxHeight < 46;
              final title = Text(
                a.clientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  decoration: faded ? TextDecoration.lineThrough : null,
                ),
              );
              if (compact) {
                return Row(
                  children: [
                    Text('${Fmt.time(a.startsAt)} ', style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Expanded(child: title),
                    Icon(a.status.icon, size: 12, color: statusColor),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(Fmt.timeRange(a.startsAt, a.endsAt),
                            style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      Icon(a.status.icon, size: 14, color: statusColor),
                    ],
                  ),
                  title,
                  Text(a.serviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
