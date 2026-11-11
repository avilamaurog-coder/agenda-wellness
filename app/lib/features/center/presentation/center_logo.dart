import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Logo del centro con respaldo al isotipo de la app.
class CenterLogo extends StatelessWidget {
  const CenterLogo({super.key, this.url, this.size = 72, this.radius});
  final String? url;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius ?? size * 0.3);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.sage, borderRadius: r),
      child: Icon(Icons.spa_rounded, color: Colors.white, size: size * 0.52),
    );
    if (url == null || url!.isEmpty || url!.endsWith('.svg')) return fallback;

    return ClipRRect(
      borderRadius: r,
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholder: (_, __) => SizedBox(width: size, height: size),
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}
