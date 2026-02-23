import 'exchange_rate_quote.dart';

abstract interface class ExchangeRateService {
  /// Returns a quote for converting 1 unit of [from] into [to].
  Future<ExchangeRateQuote> getRate({
    required String from,
    required String to,
  });
}

