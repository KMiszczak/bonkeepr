import 'package:flutter/material.dart';

import 'warranty_model.dart';

class CategoryVisual {
  const CategoryVisual({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

class CategoryVisuals {
  CategoryVisuals._();

  static const Map<Category, CategoryVisual> byCategory = {
    Category.elektronik: CategoryVisual(
      icon: Icons.devices_rounded,
      color: Color(0xFF6366F1),
    ),
    Category.haushalt: CategoryVisual(
      icon: Icons.kitchen_rounded,
      color: Color(0xFFF97316),
    ),
    Category.moebel: CategoryVisual(
      icon: Icons.chair_rounded,
      color: Color(0xFFB7791F),
    ),
    Category.werkzeug: CategoryVisual(
      icon: Icons.handyman_rounded,
      color: Color(0xFF16A34A),
    ),
    Category.fahrzeug: CategoryVisual(
      icon: Icons.directions_car_rounded,
      color: Color(0xFFDC2626),
    ),
    Category.kleidung: CategoryVisual(
      icon: Icons.checkroom_rounded,
      color: Color(0xFFDB2777),
    ),
    Category.sonstiges: CategoryVisual(
      icon: Icons.inventory_2_outlined,
      color: Color(0xFF94A3B8),
    ),
  };

  static CategoryVisual forCategory(Category category) => byCategory[category]!;
}
