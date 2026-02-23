class Project {
  const Project({
    this.id,
    required this.name,
    required this.hourlyRate,
    required this.baseCurrency,
    required this.totalHours,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final double hourlyRate;
  final String baseCurrency;
  final double totalHours;
  final DateTime updatedAt;

  double get totalIncome => hourlyRate * totalHours;

  Project copyWith({
    int? id,
    String? name,
    double? hourlyRate,
    String? baseCurrency,
    double? totalHours,
    DateTime? updatedAt,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      totalHours: totalHours ?? this.totalHours,
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
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }
}

