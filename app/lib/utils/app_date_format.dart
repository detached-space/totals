import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:kenat/kenat.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/theme/app_calendar_option.dart';
import 'package:totals/theme/app_language_option.dart';

class AppDateFormat {
  static const List<String> ethiopianMonthFull = <String>[
    'Meskerem',
    'Tikimt',
    'Hidar',
    'Tahsas',
    'Tir',
    'Yekatit',
    'Megabit',
    'Miazia',
    'Ginbot',
    'Sene',
    'Hamle',
    'Nehase',
    'Pagume',
  ];

  static const List<String> ethiopianMonthFullAmharic = <String>[
    'መስከረም',
    'ጥቅምት',
    'ኅዳር',
    'ታኅሣሥ',
    'ጥር',
    'የካቲት',
    'መጋቢት',
    'ሚያዝያ',
    'ግንቦት',
    'ሰኔ',
    'ሐምሌ',
    'ነሐሴ',
    'ጳጉሜን',
  ];

  static const List<String> ethiopianMonthShort = <String>[
    'Mes',
    'Tik',
    'Hid',
    'Tah',
    'Tir',
    'Yek',
    'Meg',
    'Mia',
    'Gin',
    'Sen',
    'Ham',
    'Neh',
    'Pag',
  ];

  static const List<String> ethiopianMonthShortAmharic = <String>[
    'መስከ',
    'ጥቅም',
    'ኅዳር',
    'ታኅሣ',
    'ጥር',
    'የካቲ',
    'መጋቢ',
    'ሚያዝ',
    'ግንቦ',
    'ሰኔ',
    'ሐምሌ',
    'ነሐሴ',
    'ጳጉሜ',
  ];

  static const List<String> gregorianMonthFullAmharic = <String>[
    'ጃንዋሪ',
    'ፌብሩዋሪ',
    'ማርች',
    'ኤፕሪል',
    'ሜይ',
    'ጁን',
    'ጁላይ',
    'ኦገስት',
    'ሴፕቴምበር',
    'ኦክቶበር',
    'ኖቬምበር',
    'ዲሴምበር',
  ];

  static const List<String> gregorianMonthShortAmharic = <String>[
    'ጃን',
    'ፌብ',
    'ማር',
    'ኤፕ',
    'ሜይ',
    'ጁን',
    'ጁላ',
    'ኦገ',
    'ሴፕ',
    'ኦክ',
    'ኖቬ',
    'ዲሴ',
  ];

  static const List<String> gregorianMonthShortEnglish = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const List<String> gregorianMonthFullEnglish = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const List<String> weekdayShortEnglishMondayFirst = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const List<String> weekdayFullEnglishMondayFirst = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static AppCalendarOption calendarOf(BuildContext? context) {
    if (context == null) return AppCalendarOption.gregorian;
    try {
      return context.read<ThemeProvider>().appCalendar;
    } catch (_) {
      return AppCalendarOption.gregorian;
    }
  }

  static AppLanguageOption languageOf(BuildContext? context) {
    if (context == null) return AppLanguageOption.english;
    try {
      return context.read<ThemeProvider>().appLanguage;
    } catch (_) {
      return AppLanguageOption.english;
    }
  }

  static bool usesEthiopianCalendar(BuildContext? context) =>
      calendarOf(context) == AppCalendarOption.ethiopian;

  static String ethiopianTime(
    DateTime date, {
    BuildContext? context,
    bool showPeriodLabel = true,
  }) {
    final time = Time.fromGregorian(date.hour, date.minute);
    final text = time.format({
      'useGeez': false,
      'lang': 'amharic',
      'showPeriodLabel': showPeriodLabel,
    });
    if (languageOf(context) == AppLanguageOption.amharic) return text;
    return text
        .replaceAll(PeriodLabels.day, 'morning')
        .replaceAll(PeriodLabels.night, 'evening')
        .replaceAll('ጠዋት', 'morning')
        .replaceAll('ማታ', 'evening');
  }

  static String ethiopianPeriodLabel(DateTime date, {BuildContext? context}) {
    final time = Time.fromGregorian(date.hour, date.minute);
    final isNight = time.period == 'night';
    if (languageOf(context) == AppLanguageOption.amharic) {
      return isNight ? PeriodLabels.night : PeriodLabels.day;
    }
    return isNight ? 'evening' : 'morning';
  }

  static List<String> ethiopianMonthNames({
    required AppLanguageOption language,
    bool abbreviated = true,
  }) {
    if (language == AppLanguageOption.amharic) {
      return abbreviated
          ? ethiopianMonthShortAmharic
          : ethiopianMonthFullAmharic;
    }
    return abbreviated ? ethiopianMonthShort : ethiopianMonthFull;
  }

  static String ethiopianMonthName(
    int month, {
    bool abbreviated = true,
    AppLanguageOption language = AppLanguageOption.english,
  }) {
    final months = ethiopianMonthNames(
      language: language,
      abbreviated: abbreviated,
    );
    if (month < 1 || month > months.length) return '';
    return months[month - 1];
  }

  static String ethiopianMonthFullName(
    int month, {
    AppLanguageOption language = AppLanguageOption.english,
  }) {
    return ethiopianMonthName(
      month,
      language: language,
      abbreviated: false,
    );
  }

  static String gregorianMonthName(
    int month, {
    required AppLanguageOption language,
    bool abbreviated = false,
  }) {
    if (month < 1 || month > 12) return '';
    if (language == AppLanguageOption.amharic) {
      return abbreviated
          ? gregorianMonthShortAmharic[month - 1]
          : gregorianMonthFullAmharic[month - 1];
    }
    return abbreviated
        ? gregorianMonthShortEnglish[month - 1]
        : gregorianMonthFullEnglish[month - 1];
  }

  static String monthShort(DateTime date, {BuildContext? context}) {
    final calendar = calendarOf(context);
    if (calendar == AppCalendarOption.ethiopian) {
      final ec = _toEthiopian(date);
      return ethiopianMonthName(
        ec['month']!,
        language: languageOf(context),
      );
    }
    return gregorianMonthName(
      date.month,
      language: languageOf(context),
      abbreviated: true,
    );
  }

  static String monthFull(DateTime date, {BuildContext? context}) {
    final calendar = calendarOf(context);
    if (calendar == AppCalendarOption.ethiopian) {
      final ec = _toEthiopian(date);
      return ethiopianMonthFullName(
        ec['month']!,
        language: languageOf(context),
      );
    }
    return gregorianMonthName(
      date.month,
      language: languageOf(context),
    );
  }

  static String monthYear(DateTime date, {BuildContext? context}) {
    final calendar = calendarOf(context);
    if (calendar == AppCalendarOption.ethiopian) {
      final ec = _toEthiopian(date);
      return '${ethiopianMonthFullName(ec['month']!, language: languageOf(context))} ${ec['year']}';
    }
    return '${gregorianMonthName(date.month, language: languageOf(context))} ${date.year}';
  }

  static String shortMonthYear(DateTime date, {BuildContext? context}) {
    final calendar = calendarOf(context);
    if (calendar == AppCalendarOption.ethiopian) {
      final ec = _toEthiopian(date);
      return '${ethiopianMonthName(ec['month']!, language: languageOf(context))} ${ec['year']}';
    }
    return '${gregorianMonthName(date.month, language: languageOf(context), abbreviated: true)} ${date.year}';
  }

  static String monthDay(DateTime date, {BuildContext? context}) {
    final calendar = calendarOf(context);
    if (calendar == AppCalendarOption.ethiopian) {
      final ec = _toEthiopian(date);
      return '${ethiopianMonthName(ec['month']!, language: languageOf(context))} ${ec['day']}';
    }
    return '${gregorianMonthName(date.month, language: languageOf(context), abbreviated: true)} ${date.day}';
  }

  static String monthDayYear(DateTime date, {BuildContext? context}) {
    final calendar = calendarOf(context);
    if (calendar == AppCalendarOption.ethiopian) {
      final ec = _toEthiopian(date);
      return '${ethiopianMonthName(ec['month']!, language: languageOf(context))} ${ec['day']}, ${ec['year']}';
    }
    final language = languageOf(context);
    return '${gregorianMonthName(date.month, language: language, abbreviated: language != AppLanguageOption.amharic)} ${date.day}, ${date.year}';
  }

  static String monthDayMaybeYear(DateTime date, {BuildContext? context}) {
    final calendar = calendarOf(context);
    if (calendar == AppCalendarOption.ethiopian) {
      final ec = _toEthiopian(date);
      final currentEcYear = Kenat.now().getEthiopian()['year'];
      final yearSuffix = ec['year'] != currentEcYear ? ', ${ec['year']}' : '';
      return '${ethiopianMonthName(ec['month']!, language: languageOf(context))} ${ec['day']}$yearSuffix';
    }
    final now = DateTime.now();
    final yearSuffix = date.year != now.year ? ', ${date.year}' : '';
    final language = languageOf(context);
    return '${gregorianMonthName(date.month, language: language, abbreviated: language != AppLanguageOption.amharic)} ${date.day}$yearSuffix';
  }

  static String yearRangeLabel(DateTime date, {BuildContext? context}) {
    final calendar = calendarOf(context);
    if (calendar == AppCalendarOption.ethiopian) {
      final ec = _toEthiopian(date);
      final months = ethiopianMonthNames(
        language: languageOf(context),
      );
      return '${months.first} - ${months.last} ${ec['year']}';
    }
    return languageOf(context) == AppLanguageOption.amharic
        ? '${gregorianMonthShortAmharic.first} - ${gregorianMonthShortAmharic.last} ${date.year}'
        : 'Jan - Dec ${date.year}';
  }

  static String dateRange(DateTime start, DateTime end,
      {BuildContext? context}) {
    final calendar = calendarOf(context);
    if (calendar == AppCalendarOption.ethiopian) {
      final ecStart = _toEthiopian(start);
      final ecEnd = _toEthiopian(end);
      final language = languageOf(context);
      final startMonth = ethiopianMonthName(
        ecStart['month']!,
        language: language,
      );
      final endMonth = ethiopianMonthName(
        ecEnd['month']!,
        language: language,
      );
      if (ecStart['year'] == ecEnd['year']) {
        if (ecStart['month'] == ecEnd['month']) {
          return '$startMonth ${ecStart['day']} - ${ecEnd['day']}, ${ecEnd['year']}';
        }
        return '$startMonth ${ecStart['day']} - $endMonth ${ecEnd['day']}, ${ecEnd['year']}';
      }
      return '$startMonth ${ecStart['day']}, ${ecStart['year']} - $endMonth ${ecEnd['day']}, ${ecEnd['year']}';
    }

    final language = languageOf(context);
    final startMonth = gregorianMonthName(
      start.month,
      language: language,
      abbreviated: true,
    );
    final endMonth = gregorianMonthName(
      end.month,
      language: language,
      abbreviated: true,
    );
    if (start.year == end.year) {
      if (start.month == end.month) {
        return '$startMonth ${start.day} - ${end.day}, ${end.year}';
      }
      return '$startMonth ${start.day} - $endMonth ${end.day}, ${end.year}';
    }
    return '$startMonth ${start.day}, ${start.year} - $endMonth ${end.day}, ${end.year}';
  }

  static String fallbackFullMonthYear(DateTime date, {BuildContext? context}) {
    if (context != null) return monthYear(date, context: context);
    return DateFormat('MMMM yyyy').format(date);
  }

  static Map<String, int> _toEthiopian(DateTime date) {
    final ec =
        Kenat.fromGregorian(date.year, date.month, date.day).getEthiopian();
    return {
      'year': ec['year'] as int,
      'month': ec['month'] as int,
      'day': ec['day'] as int,
    };
  }
}
