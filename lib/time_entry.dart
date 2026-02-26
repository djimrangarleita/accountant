class TimeEntry {
  const TimeEntry({
    this.id,
    required this.projectId,
    required this.hours,
    this.note = '',
    required this.date,
    required this.createdAt,
  });

  final int? id;
  final int projectId;
  final double hours;
  final String note;
  final DateTime date;
  final DateTime createdAt;

  TimeEntry copyWith({
    int? id,
    int? projectId,
    double? hours,
    String? note,
    DateTime? date,
    DateTime? createdAt,
  }) {
    return TimeEntry(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      hours: hours ?? this.hours,
      note: note ?? this.note,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'projectId': projectId,
      'hours': hours,
      'note': note,
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }

  factory TimeEntry.fromMap(Map<String, Object?> map) {
    return TimeEntry(
      id: map['id'] as int?,
      projectId: (map['projectId'] as num).toInt(),
      hours: (map['hours'] as num).toDouble(),
      note: map['note'] as String? ?? '',
      date: DateTime.parse(map['date'] as String),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
