import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'income_entry.dart';
import 'monthly_snapshot.dart';
import 'project.dart';
import 'time_entry.dart';

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
  static const String lastActiveMonthKey = 'last_active_month';

  static const String _projectsTable = 'projects';
  static const String _fxCacheTable = 'fx_cache';
  static const String _snapshotsTable = 'monthly_snapshots';
  static const String _timeEntriesTable = 'time_entries';

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
      version: 10,
      onCreate: (db, version) async {
        await _createIncomeEntriesTable(db);
        await _createConfigTable(db);
        await _createProjectsTable(db);
        await _createFxCacheTable(db);
        await _createMonthlySnapshotsTable(db);
        await _createTimeEntriesTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createConfigTable(db);
        }
        if (oldVersion < 3) {
          await _createProjectsTable(db);
        }
        if (oldVersion < 4) {
          await _createFxCacheTable(db);
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE $_projectsTable ADD COLUMN fxAdjustmentPercent REAL NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 6) {
          await db.execute(
            'ALTER TABLE $_projectsTable ADD COLUMN bonus REAL NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 7) {
          await _createMonthlySnapshotsTable(db);
        }
        if (oldVersion < 8) {
          await db.execute(
            'ALTER TABLE $_snapshotsTable ADD COLUMN isClosed INTEGER NOT NULL DEFAULT 1',
          );
        }
        if (oldVersion < 9) {
          await _recreateSnapshotsWithoutUnique(db);
        }
        if (oldVersion < 10) {
          await _createTimeEntriesTable(db);
          await _migrateExistingHoursToTimeEntries(db);
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

  Future<void> _createProjectsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_projectsTable(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        hourlyRate REAL NOT NULL,
        baseCurrency TEXT NOT NULL,
        totalHours REAL NOT NULL,
        fxAdjustmentPercent REAL NOT NULL DEFAULT 0,
        bonus REAL NOT NULL DEFAULT 0,
        updatedAt TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createFxCacheTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_fxCacheTable(
        pair TEXT PRIMARY KEY,
        rate REAL NOT NULL,
        asOf TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createMonthlySnapshotsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_snapshotsTable(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        projectId INTEGER NOT NULL,
        month TEXT NOT NULL,
        name TEXT NOT NULL,
        hourlyRate REAL NOT NULL,
        baseCurrency TEXT NOT NULL,
        totalHours REAL NOT NULL,
        fxAdjustmentPercent REAL NOT NULL DEFAULT 0,
        bonus REAL NOT NULL DEFAULT 0,
        totalIncomeBase REAL NOT NULL,
        baseToXafRate REAL NOT NULL DEFAULT 0,
        totalIncomeXaf REAL NOT NULL DEFAULT 0,
        closedAt TEXT NOT NULL,
        isClosed INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  Future<void> _recreateSnapshotsWithoutUnique(Database db) async {
    await db.execute('''
      CREATE TABLE ${_snapshotsTable}_new(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        projectId INTEGER NOT NULL,
        month TEXT NOT NULL,
        name TEXT NOT NULL,
        hourlyRate REAL NOT NULL,
        baseCurrency TEXT NOT NULL,
        totalHours REAL NOT NULL,
        fxAdjustmentPercent REAL NOT NULL DEFAULT 0,
        bonus REAL NOT NULL DEFAULT 0,
        totalIncomeBase REAL NOT NULL,
        baseToXafRate REAL NOT NULL DEFAULT 0,
        totalIncomeXaf REAL NOT NULL DEFAULT 0,
        closedAt TEXT NOT NULL,
        isClosed INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute(
      'INSERT INTO ${_snapshotsTable}_new SELECT * FROM $_snapshotsTable',
    );
    await db.execute('DROP TABLE $_snapshotsTable');
    await db.execute(
      'ALTER TABLE ${_snapshotsTable}_new RENAME TO $_snapshotsTable',
    );
  }

  Future<void> _createTimeEntriesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_timeEntriesTable(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        projectId INTEGER NOT NULL,
        hours REAL NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
  }

  /// One-time migration: converts each project's existing totalHours into a
  /// single legacy time entry so hours are not lost.
  Future<void> _migrateExistingHoursToTimeEntries(Database db) async {
    final projects = await db.query(_projectsTable);
    final now = DateTime.now().toUtc().toIso8601String();
    final today =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
    for (final p in projects) {
      final hours = (p['totalHours'] as num?)?.toDouble() ?? 0.0;
      if (hours <= 0) continue;
      final projectId = p['id'] as int;
      await db.insert(_timeEntriesTable, {
        'projectId': projectId,
        'hours': hours,
        'note': 'Migrated from previous total',
        'date': today,
        'createdAt': now,
      });
    }
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

  Future<void> setLastActiveMonth(String month) =>
      _setConfigString(lastActiveMonthKey, month);

  Future<String?> getLastActiveMonth() =>
      _getConfigString(lastActiveMonthKey);

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

  Future<void> setCachedFxRate({
    required String from,
    required String to,
    required double rate,
    required DateTime asOf,
  }) async {
    final pair = '${from.toUpperCase()}_${to.toUpperCase()}';
    final db = await database;
    await db.insert(
      _fxCacheTable,
      {
        'pair': pair,
        'rate': rate,
        'asOf': asOf.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<({double rate, DateTime asOf})?> getCachedFxRate({
    required String from,
    required String to,
  }) async {
    final pair = '${from.toUpperCase()}_${to.toUpperCase()}';
    final db = await database;
    final maps = await db.query(
      _fxCacheTable,
      where: 'pair = ?',
      whereArgs: [pair],
      limit: 1,
    );
    if (maps.isEmpty) return null;

    final rate = maps.first['rate'];
    final asOfRaw = maps.first['asOf'];
    if (rate is! num || asOfRaw is! String) return null;

    final asOf = DateTime.tryParse(asOfRaw);
    if (asOf == null) return null;
    return (rate: rate.toDouble(), asOf: asOf);
  }

  // Projects API.
  Future<Project> createProject({
    required String name,
    required double hourlyRate,
    required String baseCurrency,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc();
    final id = await db.insert(
      _projectsTable,
      {
        'name': name,
        'hourlyRate': hourlyRate,
        'baseCurrency': baseCurrency,
        'totalHours': 0.0,
        'fxAdjustmentPercent': 0.0,
        'bonus': 0.0,
        'updatedAt': now.toIso8601String(),
      },
    );
    return Project(
      id: id,
      name: name,
      hourlyRate: hourlyRate,
      baseCurrency: baseCurrency,
      totalHours: 0.0,
      updatedAt: now,
    );
  }

  Future<List<Project>> getProjects() async {
    final db = await database;
    final maps = await db.query(
      _projectsTable,
      orderBy: 'updatedAt DESC',
    );
    return maps.map(Project.fromMap).toList();
  }

  Future<void> updateProject(Project project) async {
    if (project.id == null) {
      throw ArgumentError('Project id is required for update.');
    }
    final db = await database;
    await db.update(
      _projectsTable,
      project.toMap(),
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  Future<Project?> getProjectById(int id) async {
    final db = await database;
    final maps = await db.query(
      _projectsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Project.fromMap(maps.first);
  }

  Future<void> deleteProject(int id) async {
    final db = await database;
    await db.delete(
      _projectsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Time entries API.

  Future<int> insertTimeEntry(TimeEntry entry) async {
    final db = await database;
    return db.insert(_timeEntriesTable, entry.toMap());
  }

  Future<void> updateTimeEntry(TimeEntry entry) async {
    if (entry.id == null) {
      throw ArgumentError('TimeEntry id is required for update.');
    }
    final db = await database;
    await db.update(
      _timeEntriesTable,
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<void> deleteTimeEntry(int id) async {
    final db = await database;
    await db.delete(
      _timeEntriesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<TimeEntry>> getTimeEntriesForProject(int projectId) async {
    final db = await database;
    final maps = await db.query(
      _timeEntriesTable,
      where: 'projectId = ?',
      whereArgs: [projectId],
      orderBy: 'date DESC, createdAt DESC',
    );
    return maps.map(TimeEntry.fromMap).toList();
  }

  Future<double> getTotalHoursForProject(int projectId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(hours) AS total FROM $_timeEntriesTable WHERE projectId = ?',
      [projectId],
    );
    if (result.isEmpty) return 0.0;
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Returns the projectId that has the most recent time entry, or null.
  Future<int?> getMostRecentlyUsedProjectId() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT projectId FROM $_timeEntriesTable ORDER BY createdAt DESC LIMIT 1',
    );
    if (result.isEmpty) return null;
    return (result.first['projectId'] as num?)?.toInt();
  }

  /// Recalculates and persists totalHours on the project from its time entries.
  Future<double> syncProjectTotalHours(int projectId) async {
    final total = await getTotalHoursForProject(projectId);
    final db = await database;
    await db.update(
      _projectsTable,
      {'totalHours': total, 'updatedAt': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [projectId],
    );
    return total;
  }

  // Monthly snapshots API.

  /// Returns true only if the month has been explicitly closed (frozen).
  Future<bool> isMonthClosed(String month) async {
    final db = await database;
    final result = await db.query(
      _snapshotsTable,
      where: 'month = ? AND isClosed = 1',
      whereArgs: [month],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Returns true if any snapshot rows exist for [month] (pending or closed).
  Future<bool> isMonthSnapshotted(String month) async {
    final db = await database;
    final result = await db.query(
      _snapshotsTable,
      where: 'month = ?',
      whereArgs: [month],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<List<MonthlySnapshot>> getSnapshotsForMonth(String month) async {
    final db = await database;
    final maps = await db.query(
      _snapshotsTable,
      where: 'month = ?',
      whereArgs: [month],
      orderBy: 'totalIncomeXaf DESC',
    );
    return maps.map(MonthlySnapshot.fromMap).toList();
  }

  Future<
      List<({
        String month,
        bool isClosed,
        double totalXaf,
        int projectCount,
      })>> getArchivedMonths() async {
    final db = await database;
    final maps = await db.rawQuery(
      'SELECT month, MIN(isClosed) AS isClosed, '
      'SUM(totalIncomeXaf) AS totalXaf, '
      'COUNT(*) AS projectCount '
      'FROM $_snapshotsTable GROUP BY month ORDER BY month DESC',
    );
    return maps.map((m) {
      return (
        month: m['month'] as String,
        isClosed: (m['isClosed'] as int?) != 0,
        totalXaf: (m['totalXaf'] as num?)?.toDouble() ?? 0.0,
        projectCount: (m['projectCount'] as int?) ?? 0,
      );
    }).toList();
  }

  Future<int> insertSnapshot(MonthlySnapshot snapshot) async {
    final db = await database;
    return db.insert(_snapshotsTable, snapshot.toMap());
  }

  Future<void> updateSnapshot(MonthlySnapshot snapshot) async {
    if (snapshot.id == null) {
      throw ArgumentError('Snapshot id is required for update.');
    }
    final db = await database;
    await db.update(
      _snapshotsTable,
      snapshot.toMap(),
      where: 'id = ?',
      whereArgs: [snapshot.id],
    );
  }

  Future<void> deleteSnapshot(int id) async {
    final db = await database;
    await db.delete(
      _snapshotsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks all pending snapshots for [month] as closed (frozen).
  Future<void> closeMonth(String month) async {
    final db = await database;
    await db.update(
      _snapshotsTable,
      {
        'isClosed': 1,
        'closedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'month = ? AND isClosed = 0',
      whereArgs: [month],
    );
  }

  /// Atomically snapshots all [projects] for [month] as pending (isClosed = 0)
  /// and resets live project hours and bonus to 0.
  Future<void> autoSnapshotAndReset({
    required String month,
    required List<MonthlySnapshot> snapshots,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final s in snapshots) {
        await txn.insert(
          _snapshotsTable,
          s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      final projectIds = snapshots.map((s) => s.projectId).toSet();
      for (final pid in projectIds) {
        await txn.update(
          _projectsTable,
          {
            'totalHours': 0.0,
            'bonus': 0.0,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [pid],
        );
        await txn.delete(
          _timeEntriesTable,
          where: 'projectId = ?',
          whereArgs: [pid],
        );
      }
    });
  }
}

