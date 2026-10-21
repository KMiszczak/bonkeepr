import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'warranty_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async => _database ??= await openDatabase(
    join(await getDatabasesPath(), 'garantieheld.db'),
    version: 1,
    onCreate: (db, v) => db.execute(
      'CREATE TABLE warranties (id TEXT PRIMARY KEY, title TEXT, storeName TEXT, price REAL, purchaseDate TEXT, warrantyMonths INTEGER, category TEXT, imagePath TEXT, serialNumber TEXT, notes TEXT, reminderDaysBefore INTEGER)'
    ),
  );

  Future<int> insertWarranty(Warranty w) async => (await database).insert('warranties', w.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  Future<List<Warranty>> getAllWarranties() async => (await (await database).query('warranties', orderBy: 'purchaseDate DESC')).map((j) => Warranty.fromMap(j)).toList();
}
