import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../agenda/domain/entities/appointment.dart';
import '../data/supabase_payment_repository.dart';
import '../domain/payment.dart';

/// Registra un cobro (total o parcial) asociado a un turno.
Future<bool?> showPaymentSheet(BuildContext context, {required Appointment appointment}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _PaymentSheet(appointment: appointment),
      ),
    );

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.appointment});
  final Appointment appointment;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  late final _amount = TextEditingController(text: widget.appointment.balance.toStringAsFixed(0));
  final _reference = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = Validators.parseMoney(_amount.text);
    if (amount == null || amount <= 0) {
      context.showSnack('Ingresá un monto válido', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(paymentRepositoryProvider).register(Payment(
            clientId: widget.appointment.clientId,
            appointmentId: widget.appointment.id,
            amount: amount,
            method: _method,
            reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
          ));
      if (mounted) {
        Navigator.pop(context, true);
        context.showSnack('Pago registrado: ${Fmt.money(amount)} (${_method.label})');
      }
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Registrar pago', style: Theme.of(context).textTheme.titleLarge),
            Text('${a.clientName} · ${a.serviceName}'),
            const SizedBox(height: 20),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: Theme.of(context).textTheme.headlineSmall,
              decoration: InputDecoration(labelText: 'Monto', prefixText: r'$ ', helperText: 'Saldo: ${Fmt.money(a.balance)}'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in PaymentMethod.values)
                  ChoiceChip(
                    avatar: Icon(m.icon, size: 18),
                    label: Text(m.label),
                    selected: _method == m,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),
            if (_method != PaymentMethod.cash) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _reference,
                decoration: const InputDecoration(labelText: 'Nº de operación / comprobante (opcional)'),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Confirmar pago')),
          ],
        ),
      ),
    );
  }
}
