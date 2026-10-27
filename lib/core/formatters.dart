import 'package:intl/intl.dart';

final _day = DateFormat('d MMMM y', 'tr_TR');
final _dayShort = DateFormat('d MMM', 'tr_TR');
final _weekday = DateFormat('EEEE', 'tr_TR');
final _dateTime = DateFormat('d MMM y HH:mm', 'tr_TR');
final _iso = DateFormat('yyyy-MM-dd');

String formatDay(DateTime d) => _day.format(d);
String formatDayShort(DateTime d) => _dayShort.format(d);
String formatWeekday(DateTime d) => _weekday.format(d);
String formatDateTime(DateTime d) => _dateTime.format(d.toLocal());
String isoDate(DateTime d) => _iso.format(d);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime parseDate(String s) => dateOnly(DateTime.parse(s));

/// "Bugün", "Dün" ya da kısa tarih.
String relativeDayLabel(DateTime day, DateTime today) {
  final diff = dateOnly(today).difference(dateOnly(day)).inDays;
  if (diff == 0) return 'Bugün';
  if (diff == 1) return 'Dün';
  return formatDayShort(day);
}

String formatLastActivity(DateTime? d) {
  if (d == null) return 'Hiç';
  final diff = DateTime.now().difference(d.toLocal());
  if (diff.inMinutes < 1) return 'Az önce';
  if (diff.inHours < 1) return '${diff.inMinutes} dk önce';
  if (diff.inDays < 1) return '${diff.inHours} saat önce';
  if (diff.inDays < 30) return '${diff.inDays} gün önce';
  return formatDay(d.toLocal());
}
