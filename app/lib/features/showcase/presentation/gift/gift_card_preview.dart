import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;

import '../../../../core/utils/formatters.dart';

/// Posiciones de los datos variables sobre la plantilla (fracciones del ancho/alto, relación 3:2).
/// Si cambia el diseño de la plantilla, ajustar estos rectángulos.
abstract final class GiftCardLayout {
  static const name = Rect.fromLTWH(0.24, 0.27, 0.64, 0.09);
  static const validFrom = Rect.fromLTWH(0.66, 0.58, 0.30, 0.07);
  static const validUntil = Rect.fromLTWH(0.66, 0.69, 0.30, 0.07);
}

/// Tarjeta con los datos cargados encima de la plantilla del producto.
class GiftCardPreview extends StatelessWidget {
  const GiftCardPreview({
    super.key,
    this.templateUrl,
    this.templateBytes,
    required this.recipientName,
    this.validFrom,
    this.validUntil,
  });

  final String? templateUrl;
  final Uint8List? templateBytes;
  final String recipientName;
  final DateTime? validFrom;
  final DateTime? validUntil;

  @override
  Widget build(BuildContext context) {
    final background = templateBytes != null
        ? Image.memory(templateBytes!, fit: BoxFit.cover)
        : templateUrl != null
            ? CachedNetworkImage(imageUrl: templateUrl!, fit: BoxFit.cover)
            : const ColoredBox(
                color: Colors.white,
                child: Center(child: Text('Cargá la plantilla en el producto')),
              );

    final ink = GoogleFonts.lora(fontWeight: FontWeight.w700, color: const Color(0xFF222222));

    return AspectRatio(
      aspectRatio: 3 / 2,
      child: LayoutBuilder(
        builder: (context, c) {
          Widget at(Rect r, String text) => Positioned(
                left: r.left * c.maxWidth,
                top: r.top * c.maxHeight,
                width: r.width * c.maxWidth,
                height: r.height * c.maxHeight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(text, style: ink),
                ),
              );
          return Stack(
            fit: StackFit.expand,
            children: [
              background,
              at(GiftCardLayout.name, recipientName.trim()),
              at(GiftCardLayout.validFrom, validFrom == null ? '' : Fmt.date(validFrom!)),
              at(GiftCardLayout.validUntil, validUntil == null ? '' : Fmt.date(validUntil!)),
            ],
          );
        },
      ),
    );
  }
}

/// Convierte el widget marcado con [key] (RepaintBoundary) en un JPG.
Future<Uint8List> captureGiftCardJpg(GlobalKey key, {double pixelRatio = 3}) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final decoded = img.decodePng(data!.buffer.asUint8List());
  if (decoded == null) throw StateError('No se pudo generar la imagen de la tarjeta');
  return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
}
