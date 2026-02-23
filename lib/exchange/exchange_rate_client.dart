import 'exchange_rate_quote.dart';
import 'exchange_rate_service.dart';

/// Thin wrapper around [ExchangeRateService] so your app depends on one entrypoint.
///
/// Swapping providers is just:
/// `ExchangeRateClient(service: SomeOtherService(...))`
class ExchangeRateClient {
  const ExchangeRateClient({required ExchangeRateService service})
      : _service = service;

  final ExchangeRateService _service;

  Future<ExchangeRateQuote> getRate({
    required String from,
    required String to,
  }) =>
      _service.getRate(from: from, to: to);
}

