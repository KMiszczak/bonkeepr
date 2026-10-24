import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'warranty_model.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static const _databaseName = 'garantieheld.db';
  static const _tableName = 'warranties';

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final databasesPath = await getDatabasesPath();
    final database = await openDatabase(
      path.join(databasesPath, _databaseName),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            storeName TEXT NOT NULL,
            price REAL NOT NULL,
            purchaseDate TEXT NOT NULL,
            warrantyMonths INTEGER NOT NULL,
            category TEXT NOT NULL,
            imagePath TEXT NOT NULL,
            warrantyDays INTEGER,
            serialNumber TEXT,
            notes TEXT,
            reminderDaysBefore INTEGER NOT NULL DEFAULT 30
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN warrantyDays INTEGER',
          );
        }
      },
    );
    _database = database;
    return database;
  }

  Future<int> insertWarranty(Warranty warranty) async {
    return (await database).insert(
      _tableName,
      warranty.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateWarranty(Warranty warranty) async {
    return (await database).update(
      _tableName,
      warranty.toMap(),
      where: 'id = ?',
      whereArgs: [warranty.id],
    );
  }

  Future<List<Warranty>> getAllWarranties() async {
    final rows = await (await database).query(
      _tableName,
      orderBy: 'purchaseDate DESC',
    );
    return rows.map(Warranty.fromMap).toList(growable: false);
  }

  Future<void> importWarranties(List<Warranty> warranties) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final warranty in warranties) {
        await transaction.insert(
          _tableName,
          warranty.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<int> deleteWarranty(String id) async {
    return (await database).delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    final currentDatabase = _database;
    if (currentDatabase == null) return;
    await currentDatabase.close();
    _database = null;
  }
}
