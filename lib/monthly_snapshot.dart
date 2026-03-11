import 'package:intl/intl.dart';

class MonthlySnapshot {
  const MonthlySnapshot({
    this.id,
    required this.projectId,
    required this.month,
    required this.name,
    required this.hourlyRate,
    required this.baseCurrency,
    required this.totalHours,
    required this.fxAdjustmentPercent,
    required this.bonus,
    required this.totalIncomeBase,
    required this.baseToXafRate,
    required this.totalIncomeXaf,
    required this.closedAt,
    this.isClosed = true,
    this.secondCurrency = 'XAF',
  });

  final int? id;
  final int projectId;

  /// Format: "YYYY-MM" (e.g. "2026-02").
  final String month;

  final String name;
  final double hourlyRate;
  final String baseCurrency;
  final double totalHours;
  final double fxAdjustmentPercent;
  final double bonus;
  final double totalIncomeBase;
  final double baseToXafRate;
  final double totalIncomeXaf;
  final DateTime closedAt;
  final bool isClosed;
  final String secondCurrency;

  /// Human-readable month label, e.g. "February 2026".
  String get monthLabel {
    final parts = month.split('-');
    if (parts.length != 2) return month;
    final year = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (year == null || m == null || m < 1 || m > 12) return month;
    return DateFormat.yMMMM().format(DateTime(year, m));
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'projectId': projectId,
      'month': month,
      'name': name,
      'hourlyRate': hourlyRate,
      'baseCurrency': baseCurrency,
      'totalHours': totalHours,
      'fxAdjustmentPercent': fxAdjustmentPercent,
      'bonus': bonus,
      'totalIncomeBase': totalIncomeBase,
      'baseToXafRate': baseToXafRate,
      'totalIncomeXaf': totalIncomeXaf,
      'closedAt': closedAt.toUtc().toIso8601String(),
      'isClosed': isClosed ? 1 : 0,
      'secondCurrency': secondCurrency,
    };
  }

  factory MonthlySnapshot.fromMap(Map<String, Object?> map) {
    return MonthlySnapshot(
      id: map['id'] as int?,
      projectId: (map['projectId'] as num).toInt(),
      month: map['month'] as String,
      name: map['name'] as String? ?? '',
      hourlyRate: (map['hourlyRate'] as num).toDouble(),
      baseCurrency: map['baseCurrency'] as String? ?? 'USD',
      totalHours: (map['totalHours'] as num).toDouble(),
      fxAdjustmentPercent:
          (map['fxAdjustmentPercent'] as num?)?.toDouble() ?? 0.0,
      bonus: (map['bonus'] as num?)?.toDouble() ?? 0.0,
      totalIncomeBase: (map['totalIncomeBase'] as num).toDouble(),
      baseToXafRate: (map['baseToXafRate'] as num?)?.toDouble() ?? 0.0,
      totalIncomeXaf: (map['totalIncomeXaf'] as num?)?.toDouble() ?? 0.0,
      closedAt: DateTime.parse(map['closedAt'] as String),
      isClosed: (map['isClosed'] as int?) != 0,
      secondCurrency: map['secondCurrency'] as String? ?? 'XAF',
    );
  }
}
