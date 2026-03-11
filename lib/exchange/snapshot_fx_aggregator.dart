import '../income_database.dart';
import '../monthly_snapshot.dart';
import 'exchange_rate_client.dart';

class SnapshotFxResult {
  const SnapshotFxResult({
    required this.totalUsd,
    required this.totalSecond,
    required this.perSnapshotSecond,
  });

  final double totalUsd;
  final double totalSecond;

  /// Live-converted second-currency amount keyed by snapshot id.
  /// Only populated for unpaid snapshots; paid ones are omitted.
  final Map<int, double> perSnapshotSecond;
}

/// Converts a list of [snapshots] to aggregated USD + [secondCurrency]
/// totals using cached or live exchange rates.
///
/// Paid snapshots' individual display values are left frozen, but their
/// base-currency income is still re-converted for the aggregate totals so
/// the summary always uses a single consistent currency.
Future<SnapshotFxResult> computeSnapshotAggregates({
  required List<MonthlySnapshot> snapshots,
  required String secondCurrency,
  required ExchangeRateClient client,
  required IncomeDatabase db,
}) async {
  double totalUsd = 0;
  double totalSecond = 0;
  final perSnapshotSecond = <int, double>{};

  final rateCache = <String, double>{};

  Future<double> getRate(String from, String to) async {
    if (from == to) return 1.0;
    final key = '${from}_$to';
    if (rateCache.containsKey(key)) return rateCache[key]!;

    final cached = await db.getCachedFxRate(from: from, to: to);
    final now = DateTime.now().toUtc();
    if (cached != null && now.difference(cached.asOf).inMinutes < 60) {
      rateCache[key] = cached.rate;
      return cached.rate;
    }

    final quote = await client.getRate(from: from, to: to);
    await db.setCachedFxRate(
        from: from, to: to, rate: quote.rate, asOf: quote.asOf);
    rateCache[key] = quote.rate;
    return quote.rate;
  }

  final secondUpper = secondCurrency.toUpperCase();

  for (final s in snapshots) {
    final base = s.baseCurrency.toUpperCase();
    final income = s.totalIncomeBase;

    final bool hasStoredUsd = s.baseToUsdRate > 0 && s.totalIncomeUsd > 0;
    if (hasStoredUsd) {
      totalUsd += s.totalIncomeUsd;
    } else {
      final usdRate = await getRate(base, 'USD');
      totalUsd += income * usdRate;
    }

    final bool hasStoredSecond = s.secondCurrency.toUpperCase() == secondUpper &&
        s.baseToXafRate > 0 &&
        s.totalIncomeXaf > 0;
    final double secondAmount;
    if (hasStoredSecond) {
      secondAmount = s.totalIncomeXaf;
    } else {
      final secondRate = await getRate(base, secondUpper);
      secondAmount = income * secondRate;
    }
    totalSecond += secondAmount;

    if (!s.isClosed && s.id != null) {
      perSnapshotSecond[s.id!] = secondAmount;
    }
  }

  return SnapshotFxResult(
    totalUsd: totalUsd,
    totalSecond: totalSecond,
    perSnapshotSecond: perSnapshotSecond,
  );
}
