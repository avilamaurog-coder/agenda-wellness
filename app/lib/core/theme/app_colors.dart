import 'package:flutter/material.dart';

/// Paleta "wellness": salvia, arena y terracota, con estados de turno
/// diferenciables también para personas con daltonismo (se acompañan de ícono y texto).
abstract final class AppColors {
  // Marca
  static const sage = Color(0xFF5E7D6F);
  static const sageLight = Color(0xFFA8C3B8);
  static const sand = Color(0xFFF4EFE6);
  static const sandDark = Color(0xFFE6DCCB);
  static const terracotta = Color(0xFFC98B6B);
  static const ink = Color(0xFF26332E);

  // Superficies modo oscuro
  static const night = Color(0xFF151C19);
  static const nightSurface = Color(0xFF1E2824);

  // Estados de turno
  static const pending = Color(0xFFE0A245);
  static const confirmed = Color(0xFF4F8A8B);
  static const completed = Color(0xFF5F9A62);
  static const cancelled = Color(0xFFC0605F);
  static const noShow = Color(0xFF8C879B);
}
