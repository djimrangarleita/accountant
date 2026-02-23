import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'income_entry.dart';

class IncomeDatabase {
  IncomeDatabase._internal();

  static final IncomeDatabase instance = IncomeDatabase._internal();

  Database? _database;

  static const String _configTable = 'app_config';
  static const String _configKeyColumn = 'key';
  static const String _configValueColumn = 'value';

  static const String hourlyRateKey = 'hourly_rate';
  static const String lastHoursKey = 'last_hours';
  static const String fxAdjustmentKey = 'fx_adjustment_percent';
  static const String fxUsdXafRateKey = 'fx_usd_xaf_rate';
  static const String fxUsdXafTimestampKey = 'fx_usd_xaf_timestamp';

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    final db = await _openDatabase();
    _database = db;
    return db;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'income.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createIncomeEntriesTable(db);
        await _createConfigTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createConfigTable(db);
        }
      },
    );
  }

  Future<void> _createIncomeEntriesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS income_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        description TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createConfigTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_configTable(
        $_configKeyColumn TEXT PRIMARY KEY,
        $_configValueColumn TEXT NOT NULL
      )
    ''');
  }

  // Income entries API (currently unused by UI but kept for future use).
  Future<IncomeEntry> insertEntry(IncomeEntry entry) async {
    final db = await database;
    final id = await db.insert('income_entries', entry.toMap());
    return entry.copyWith(id: id);
  }

  Future<List<IncomeEntry>> getAllEntries() async {
    final db = await database;
    final maps = await db.query(
      'income_entries',
      orderBy: 'createdAt DESC',
    );
    return maps.map((map) => IncomeEntry.fromMap(map)).toList();
  }

  Future<void> deleteEntry(int id) async {
    final db = await database;
    await db.delete(
      'income_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // App configuration API.
  Future<void> _setConfigDouble(String key, double value) async {
    final db = await database;
    await db.insert(
      _configTable,
      {
        _configKeyColumn: key,
        _configValueColumn: value.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<double?> _getConfigDouble(String key) async {
    final db = await database;
    final maps = await db.query(
      _configTable,
      columns: [_configValueColumn],
      where: '$_configKeyColumn = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    final valueStr = maps.first[_configValueColumn] as String?;
    if (valueStr == null) return null;
    return double.tryParse(valueStr);
  }

  Future<void> _setConfigString(String key, String value) async {
    final db = await database;
    await db.insert(
      _configTable,
      {
        _configKeyColumn: key,
        _configValueColumn: value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> _getConfigString(String key) async {
    final db = await database;
    final maps = await db.query(
      _configTable,
      columns: [_configValueColumn],
      where: '$_configKeyColumn = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    final valueStr = maps.first[_configValueColumn] as String?;
    return valueStr;
  }

  Future<void> setHourlyRate(double rate) =>
      _setConfigDouble(hourlyRateKey, rate);

  Future<double?> getHourlyRate() => _getConfigDouble(hourlyRateKey);

  Future<void> setLastHours(double hours) =>
      _setConfigDouble(lastHoursKey, hours);

  Future<double?> getLastHours() => _getConfigDouble(lastHoursKey);

  Future<void> setFxAdjustmentPercent(double percent) =>
      _setConfigDouble(fxAdjustmentKey, percent);

  /// Returns the adjustment in percent (e.g. -10, 0, +10). Defaults to 0.
  Future<double> getFxAdjustmentPercent() async =>
      (await _getConfigDouble(fxAdjustmentKey)) ?? 0.0;

  Future<void> setCachedUsdToXafRate(double rate, DateTime asOf) async {
    await _setConfigDouble(fxUsdXafRateKey, rate);
    await _setConfigString(fxUsdXafTimestampKey, asOf.toUtc().toIso8601String());
  }

  Future<double?> getCachedUsdToXafRate() =>
      _getConfigDouble(fxUsdXafRateKey);

  Future<DateTime?> getCachedUsdToXafRateTimestamp() async {
    final raw = await _getConfigString(fxUsdXafTimestampKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }
}

