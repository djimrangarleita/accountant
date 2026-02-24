class Project {
  const Project({
    this.id,
    required this.name,
    required this.hourlyRate,
    required this.baseCurrency,
    required this.totalHours,
    this.fxAdjustmentPercent = 0.0,
    this.bonus = 0.0,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final double hourlyRate;
  final String baseCurrency;
  final double totalHours;
  final double fxAdjustmentPercent;
  final double bonus;
  final DateTime updatedAt;

  double get totalIncome => hourlyRate * totalHours + bonus;

  Project copyWith({
    int? id,
    String? name,
    double? hourlyRate,
    String? baseCurrency,
    double? totalHours,
    double? fxAdjustmentPercent,
    double? bonus,
    DateTime? updatedAt,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      totalHours: totalHours ?? this.totalHours,
      fxAdjustmentPercent: fxAdjustmentPercent ?? this.fxAdjustmentPercent,
      bonus: bonus ?? this.bonus,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'hourlyRate': hourlyRate,
      'baseCurrency': baseCurrency,
      'totalHours': totalHours,
      'fxAdjustmentPercent': fxAdjustmentPercent,
      'bonus': bonus,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Project.fromMap(Map<String, Object?> map) {
    return Project(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      hourlyRate: (map['hourlyRate'] as num).toDouble(),
      baseCurrency: map['baseCurrency'] as String? ?? 'USD',
      totalHours: (map['totalHours'] as num).toDouble(),
      fxAdjustmentPercent: (map['fxAdjustmentPercent'] as num?)?.toDouble() ?? 0.0,
      bonus: (map['bonus'] as num?)?.toDouble() ?? 0.0,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}

