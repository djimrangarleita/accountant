import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exchange_rate_quote.dart';
import 'exchange_rate_service.dart';

class OpenExchangeRatesService implements ExchangeRateService {
  OpenExchangeRatesService({
    required this.appId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Create from `--dart-define=OPEN_EXCHANGE_RATES_APP_ID=...`
  factory OpenExchangeRatesService.fromEnvironment({http.Client? client}) {
    const appId = String.fromEnvironment('OPEN_EXCHANGE_RATES_APP_ID');
    if (appId.isEmpty) {
      throw StateError(
        'Missing OPEN_EXCHANGE_RATES_APP_ID. '
        'Run with: --dart-define=OPEN_EXCHANGE_RATES_APP_ID=YOUR_KEY',
      );
    }
    return OpenExchangeRatesService(appId: appId, client: client);
  }

  final String appId;
  final http.Client _client;

  /// Free tier uses USD as base. We'll convert cross rates via:
  /// rate(from->to) = (USD->to) / (USD->from)
  static const String _base = 'USD';

  @override
  Future<ExchangeRateQuote> getRate({
    required String from,
    required String to,
  }) async {
    final fromNorm = from.trim().toUpperCase();
    final toNorm = to.trim().toUpperCase();

    if (fromNorm.isEmpty || toNorm.isEmpty) {
      throw ArgumentError('Currencies must be non-empty (e.g. "USD", "EUR").');
    }

    if (fromNorm == toNorm) {
      return ExchangeRateQuote(
        from: fromNorm,
        to: toNorm,
        rate: 1.0,
        asOf: DateTime.now().toUtc(),
        provider: 'openexchangerates',
      );
    }

    final uri = Uri.https(
      'openexchangerates.org',
      '/api/latest.json',
      {'app_id': appId},
    );

    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw StateError(
        'OpenExchangeRates error ${res.statusCode}: ${res.body}',
      );
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Unexpected response format from OpenExchangeRates.');
    }

    final timestampSeconds = decoded['timestamp'];
    final ratesAny = decoded['rates'];
    if (timestampSeconds is! num || ratesAny is! Map<String, dynamic>) {
      throw StateError('Unexpected response payload from OpenExchangeRates.');
    }

    double? usdTo(String currency) {
      if (currency == _base) return 1.0;
      final value = ratesAny[currency];
      if (value is num) return value.toDouble();
      return null;
    }

    final usdToTo = usdTo(toNorm);
    final usdToFrom = usdTo(fromNorm);

    if (usdToTo == null) {
      throw StateError('Missing rate for $toNorm from OpenExchangeRates.');
    }
    if (usdToFrom == null) {
      throw StateError('Missing rate for $fromNorm from OpenExchangeRates.');
    }

    final crossRate = usdToTo / usdToFrom;
    final asOf = DateTime.fromMillisecondsSinceEpoch(
      (timestampSeconds * 1000).round(),
      isUtc: true,
    );

    return ExchangeRateQuote(
      from: fromNorm,
      to: toNorm,
      rate: crossRate,
      asOf: asOf,
      provider: 'openexchangerates',
    );
  }
}

