import 'dart:convert';

enum Category { elektronik, haushalt, moebel, werkzeug, kleidung, sonstiges }

class Warranty {
  final String id, title, storeName, imagePath;
  final double price;
  final DateTime purchaseDate;
  final int warrantyMonths, reminderDaysBefore;
  final Category category;
  final String? serialNumber, notes;

  Warranty({
    required this.id,
    required this.title,
    required this.storeName,
    required this.price,
    required this.purchaseDate,
    required this.warrantyMonths,
    required this.category,
    required this.imagePath,
    this.serialNumber,
    this.notes,
    this.reminderDaysBefore = 30,
  });

  DateTime get expirationDate => DateTime(purchaseDate.year, purchaseDate.month + warrantyMonths, purchaseDate.day);
  int get remainingDays => DateTime(expirationDate.year, expirationDate.month, expirationDate.day).difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)).inDays;
  bool get isExpired => remainingDays < 0;
  bool get isExpiringSoon => remainingDays >= 0 && remainingDays <= 30;

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'storeName': storeName,
    'price': price,
    'purchaseDate': purchaseDate.toIso8601String(),
    'warrantyMonths': warrantyMonths,
    'category': category.name,
    'imagePath': imagePath,
    'serialNumber': serialNumber,
    'notes': notes,
    'reminderDaysBefore': reminderDaysBefore,
  };

  factory Warranty.fromMap(Map<String, dynamic> map) => Warranty(
    id: map['id'],
    title: map['title'],
    storeName: map['storeName'],
    price: (map['price'] as num).toDouble(),
    purchaseDate: DateTime.parse(map['purchaseDate']),
    warrantyMonths: map['warrantyMonths'],
    category: Category.values.firstWhere((e) => e.name == map['category'], orElse: () => Category.sonstiges),
    imagePath: map['imagePath'],
    serialNumber: map['serialNumber'],
    notes: map['notes'],
    reminderDaysBefore: map['reminderDaysBefore'] ?? 30,
  );
}
