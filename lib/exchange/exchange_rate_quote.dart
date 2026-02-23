class ExchangeRateQuote {
  const ExchangeRateQuote({
    required this.from,
    required this.to,
    required this.rate,
    required this.asOf,
    required this.provider,
  });

  final String from;
  final String to;

  /// Conversion rate: 1 unit of [from] equals [rate] units of [to].
  final double rate;

  /// Timestamp associated with this quote (provider timestamp).
  final DateTime asOf;

  /// Provider identifier (useful for debugging / swapping services).
  final String provider;
}

