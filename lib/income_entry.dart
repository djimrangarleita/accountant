class IncomeEntry {
  const IncomeEntry({
    this.id,
    required this.amount,
    required this.description,
    required this.createdAt,
  });

  final int? id;
  final double amount;
  final String description;
  final DateTime createdAt;

  IncomeEntry copyWith({
    int? id,
    double? amount,
    String? description,
    DateTime? createdAt,
  }) {
    return IncomeEntry(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'amount': amount,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory IncomeEntry.fromMap(Map<String, Object?> map) {
    return IncomeEntry(
      id: map['id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      description: map['description'] as String? ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}

