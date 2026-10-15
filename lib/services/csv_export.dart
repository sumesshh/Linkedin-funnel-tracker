import 'csv_data.dart';
import 'download.dart';

export 'csv_data.dart' show monthLabel;

void _save(String kind, List<List<Object?>> rows) => downloadText(
      'linkedin-$kind-${day.format(DateTime.now())}.csv',
      toCsv(rows),
      'text/csv',
    );

void exportWeeklyCsv() => _save('weekly-totals', weeklyTotalsRows());
void exportMonthlyCsv() => _save('monthly-totals', monthlyTotalsRows());
void exportRawCsv() => _save('raw-data', rawRows());
