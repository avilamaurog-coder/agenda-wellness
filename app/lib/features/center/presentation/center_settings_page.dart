import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/supabase_center_repository.dart';
import '../domain/center.dart';
import 'center_logo.dart';

/// Datos del centro (solo administradores): logo, contacto, catálogo público y Telegram.
class CenterSettingsPage extends ConsumerStatefulWidget {
  const CenterSettingsPage({super.key});

  @override
  ConsumerState<CenterSettingsPage> createState() => _CenterSettingsPageState();
}

class _CenterSettingsPageState extends ConsumerState<CenterSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{
    for (final k in [
      'name', 'legal', 'cuit', 'description', 'phone', 'email', 'address',
      'whatsapp', 'instagram', 'website', 'bot', 'adminChat', 'channel',
    ])
      k: TextEditingController(),
  };
  BusinessCenter? _center;
  bool _catalog = true;
  bool _backup = true;
  bool _saving = false;
  bool _uploading = false;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(BusinessCenter c) {
    _center = c;
    _c['name']!.text = c.name;
    _c['legal']!.text = c.legalName ?? '';
    _c['cuit']!.text = c.cuit ?? '';
    _c['description']!.text = c.description ?? '';
    _c['phone']!.text = c.phone ?? '';
    _c['email']!.text = c.email ?? '';
    _c['address']!.text = c.address ?? '';
    _c['whatsapp']!.text = c.whatsappContact ?? '';
    _c['instagram']!.text = c.instagram ?? '';
    _c['website']!.text = c.website ?? '';
    _c['bot']!.text = c.telegramBotUsername ?? '';
    _c['adminChat']!.text = c.telegramAdminChatId ?? '';
    _c['channel']!.text = c.telegramChannelId ?? '';
    _catalog = c.publicCatalogEnabled;
    _backup = c.backupEnabled;
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 92);
    if (file == null || _center == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.contains('.') ? file.name.split('.').last : 'png';
      final url = await ref.read(centerRepositoryProvider).uploadLogo(_center!.id, bytes, ext);
      ref.invalidate(centerProvider);
      ref.invalidate(publicBrandingProvider);
      setState(() => _center = BusinessCenter.fromJson({..._rowOf(_center!), 'logo_url': url}));
      if (mounted) context.showSnack('Logo actualizado');
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Map<String, dynamic> _rowOf(BusinessCenter c) => {'id': c.id, ...c.toRow()};

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _center == null) return;
    setState(() => _saving = true);
    try {
      final updated = BusinessCenter(
        id: _center!.id,
        name: _c['name']!.text,
        legalName: _c['legal']!.text,
        cuit: _c['cuit']!.text,
        description: _c['description']!.text,
        phone: _c['phone']!.text,
        email: _c['email']!.text,
        address: _c['address']!.text,
        whatsappContact: _c['whatsapp']!.text,
        instagram: _c['instagram']!.text,
        website: _c['website']!.text,
        logoUrl: _center!.logoUrl,
        publicCatalogEnabled: _catalog,
        telegramBotUsername: _c['bot']!.text,
        telegramAdminChatId: _c['adminChat']!.text,
        telegramChannelId: _c['channel']!.text,
        backupEnabled: _backup,
      );
      final saved = await ref.read(centerRepositoryProvider).update(updated);
      ref.invalidate(centerProvider);
      ref.invalidate(publicBrandingProvider);
      setState(() => _center = saved);
      if (mounted) context.showSnack('Datos del centro guardados');
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_center == null) {
      final async = ref.watch(centerProvider);
      return Scaffold(
        appBar: AppBar(title: const Text('Datos del centro')),
        body: AsyncValueView(
          value: async,
          onRetry: () => ref.invalidate(centerProvider),
          data: (c) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _center == null) setState(() => _fill(c));
            });
            return const Center(child: CircularProgressIndicator());
          },
        ),
      );
    }

    final t = Theme.of(context);
    const gap = SizedBox(height: 12);
    InputDecoration dec(String label, {IconData? icon, String? helper, String? prefix}) => InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          prefixText: prefix,
          prefixIcon: icon == null ? null : Icon(icon),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Datos del centro'),
        actions: [TextButton(onPressed: _saving ? null : _save, child: const Text('Guardar'))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            // ------------------------------------------------ Logo
            Center(
              child: Stack(
                children: [
                  CenterLogo(url: _center!.logoUrl, size: 112),
                  if (_uploading)
                    const Positioned.fill(child: Center(child: CircularProgressIndicator())),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _uploading ? null : _pickLogo,
                icon: const Icon(Icons.upload_rounded),
                label: Text(_center!.logoUrl == null ? 'Cargar logo' : 'Cambiar logo'),
              ),
            ),
            Text(
              'Se usa en la app, la pantalla de ingreso, los reportes PDF, los emails y el catálogo público. '
              'Recomendado: PNG cuadrado de 512 × 512 px con fondo transparente.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall,
            ),

            const SectionTitle('Identidad'),
            TextFormField(
              controller: _c['name'],
              decoration: dec('Nombre comercial *'),
              validator: (v) => Validators.required(v, 'El nombre'),
            ),
            gap,
            TextFormField(
              controller: _c['description'],
              maxLines: 3,
              maxLength: 280,
              decoration: dec('Descripción breve', helper: 'Aparece en el catálogo público.'),
            ),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _c['legal'], decoration: dec('Razón social'))),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(controller: _c['cuit'], decoration: dec('CUIT'))),
              ],
            ),

            const SectionTitle('Contacto'),
            TextFormField(
              controller: _c['whatsapp'],
              keyboardType: TextInputType.phone,
              decoration: dec('WhatsApp para reservas', icon: Icons.chat_outlined, helper: 'Con código de área, ej. 3764 123456'),
              validator: Validators.phone,
            ),
            gap,
            TextFormField(controller: _c['phone'], keyboardType: TextInputType.phone, decoration: dec('Teléfono', icon: Icons.phone_outlined)),
            gap,
            TextFormField(
              controller: _c['email'],
              keyboardType: TextInputType.emailAddress,
              decoration: dec('Email', icon: Icons.mail_outline),
              validator: (v) => Validators.email(v, optional: true),
            ),
            gap,
            TextFormField(controller: _c['address'], decoration: dec('Dirección', icon: Icons.place_outlined)),
            gap,
            TextFormField(controller: _c['instagram'], decoration: dec('Instagram', icon: Icons.camera_alt_outlined, prefix: '@')),
            gap,
            TextFormField(controller: _c['website'], keyboardType: TextInputType.url, decoration: dec('Sitio web', icon: Icons.language)),

            const SectionTitle('Catálogo público'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _catalog,
              title: const Text('Publicar catálogo de servicios y productos'),
              subtitle: const Text('Página web sin login para compartir con clientes'),
              onChanged: (v) => setState(() => _catalog = v),
            ),

            const SectionTitle('Telegram'),
            TextFormField(
              controller: _c['bot'],
              decoration: dec(
                'Usuario del bot',
                prefix: '@',
                icon: Icons.smart_toy_outlined,
                helper: 'Creado con @BotFather. Se usa para generar el enlace con el que cada cliente vincula su Telegram.',
              ),
            ),
            gap,
            TextFormField(
              controller: _c['adminChat'],
              decoration: dec(
                'Chat de avisos al staff (opcional)',
                icon: Icons.notifications_active_outlined,
                helper: 'ID del chat o grupo que recibe confirmaciones, cancelaciones y pedidos de cambio.',
              ),
            ),
            gap,
            TextFormField(
              controller: _c['channel'],
              decoration: dec(
                'Canal de promociones (opcional)',
                icon: Icons.campaign_outlined,
                helper: '@tucanal o ID -100…; el bot debe ser administrador del canal.',
              ),
            ),
            if (_c['bot']!.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded),
                  label: Text('Copiar enlace del bot: t.me/${_c['bot']!.text.replaceAll('@', '')}'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: 'https://t.me/${_c['bot']!.text.replaceAll('@', '')}'));
                    if (context.mounted) context.showSnack('Enlace copiado');
                  },
                ),
              ),

            const SectionTitle('Copias de seguridad'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _backup,
              title: const Text('Backup diario automático'),
              subtitle: const Text('Todas las noches a las 03:00 en tu nube'),
              onChanged: (v) => setState(() => _backup = v),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar cambios')),
          ],
        ),
      ),
    );
  }
}
