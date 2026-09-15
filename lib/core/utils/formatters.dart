import 'package:intl/intl.dart';

class AppFormatters {
  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final NumberFormat _currencyCompact = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('dd MMM yyyy, hh:mm a');
  static final DateFormat _timeFormat = DateFormat('hh:mm a');
  static final DateFormat _dbDateFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _monthYear = DateFormat('MMMM yyyy');

  static String formatCurrency(double amount) => _currency.format(amount);
  static String formatCurrencyCompact(double amount) => _currencyCompact.format(amount);

  static String formatDate(DateTime date) => _dateFormat.format(date);
  static String formatDateTime(DateTime date) => _dateTimeFormat.format(date);
  static String formatTime(DateTime date) => _timeFormat.format(date);
  static String formatDbDate(DateTime date) => _dbDateFormat.format(date);
  static String formatMonthYear(DateTime date) => _monthYear.format(date);

  static String formatQuantity(int qty) => qty.toString();

  static String formatPercent(double value) => '${value.toStringAsFixed(1)}%';

  static String formatGrowth(double percent) {
    final sign = percent >= 0 ? '+' : '';
    return '$sign${percent.toStringAsFixed(1)}%';
  }

  static String getGreeting({
    required String morning,
    required String afternoon,
    required String evening,
  }) {
    final hour = DateTime.now().hour;
    if (hour < 12) return morning;
    if (hour < 17) return afternoon;
    return evening;
  }

  static String getGreetingEmoji() {
    final hour = DateTime.now().hour;
    if (hour < 12) return '☀️';
    if (hour < 17) return '🌤️';
    return '🌙';
  }

  static String todayDbDate() => _dbDateFormat.format(DateTime.now());

  static DateTime parseDbDate(String date) => _dbDateFormat.parse(date);

  static String numberWords(String text) {
    const words = {
      'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
      'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
      'ten': '10', 'eleven': '11', 'twelve': '12',
      'ek': '1', 'do': '2', 'teen': '3', 'char': '4', 'paanch': '5',
      'chhe': '6', 'saat': '7', 'aath': '8', 'nau': '9', 'das': '10',
    };
    var result = text.toLowerCase();
    for (final entry in words.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}
