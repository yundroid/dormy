import 'package:flutter/material.dart';

/// Modüllerin veritabanında saklanan ikon adları.
const moduleIcons = <String, IconData>{
  'fact_check': Icons.fact_check_outlined,
  'bed': Icons.bed_outlined,
  'menu_book': Icons.menu_book_outlined,
  'school': Icons.school_outlined,
  'checklist': Icons.checklist,
  'cleaning': Icons.cleaning_services_outlined,
  'book': Icons.book_outlined,
  'edit_note': Icons.edit_note,
  'star': Icons.star_outline,
  'mosque': Icons.mosque_outlined,
  'sports': Icons.sports_soccer_outlined,
  'restaurant': Icons.restaurant_outlined,
  'schedule': Icons.schedule,
  'favorite': Icons.favorite_border,
  'quiz': Icons.quiz_outlined,
  'assignment': Icons.assignment_outlined,
  'library': Icons.local_library_outlined,
};

IconData moduleIcon(String name) => moduleIcons[name] ?? Icons.checklist;
