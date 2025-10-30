// ШЛЯХ: lib/core/utils/duration_format.dart

/// Утилиты для парсинга и форматирования длительности книги.
class DurationFormat {
  /// Пытается разобрать сырую строку длительности в [Duration].
  /// Поддерживает:
  /// - "159" (минуты)
  /// - "02:33" (часы:минуты) или "02:33:00"
  /// - "90:00" (минуты:секунды)
  /// - ISO 8601: "PT2H33M" / "PT45M" / "PT1H"
  /// - Текстовые варианты: "2ч 10м", "2 ч 10 мин", "2 год 10 хв"
  static Duration? parse(String? raw) {
    if (raw == null) return null;
    String s = raw.trim();
    if (s.isEmpty) return null;

    final lower = s.toLowerCase();

    // ISO 8601 "PT#H#M#S"
    final iso = RegExp(r'^pt(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$', caseSensitive: false);
    final mIso = iso.firstMatch(lower);
    if (mIso != null) {
      final h = int.tryParse(mIso.group(1) ?? '0') ?? 0;
      final m = int.tryParse(mIso.group(2) ?? '0') ?? 0;
      final sec = int.tryParse(mIso.group(3) ?? '0') ?? 0;
      return Duration(hours: h, minutes: m, seconds: sec);
    }

    // "HH:MM[:SS]" или "MM:SS"
    if (s.contains(':')) {
      final parts = s.split(':').map((e) => e.trim()).toList();
      if (parts.length == 2) {
        final a = int.tryParse(parts[0]) ?? 0;
        final b = int.tryParse(parts[1]) ?? 0;
        // Эвристика: если второе < 60 — это либо H:MM, либо M:SS.
        // Если первый >= 3 — скорее всего часы:минуты.
        if (a >= 3) {
          return Duration(hours: a, minutes: b);
        }
        // Иначе считаем "минуты:секунды"
        return Duration(minutes: a, seconds: b);
      } else if (parts.length >= 3) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final sec = int.tryParse(parts[2]) ?? 0;
        return Duration(hours: h, minutes: m, seconds: sec);
      }
    }

    // Текстовые пометки: ч/час/год, м/мин/хв и т.п.
    final rxHours = RegExp(r'(\d+)\s*(h|ч|час|часов|часа|год|година|годин|години)', caseSensitive: false);
    final rxMins  = RegExp(r'(\d+)\s*(m|min|мин|м|хв|хвилин|хвилини)', caseSensitive: false);
    final hMatch = rxHours.firstMatch(lower);
    final mMatch = rxMins.firstMatch(lower);
    if (hMatch != null || mMatch != null) {
      final h = int.tryParse(hMatch?.group(1) ?? '0') ?? 0;
      final m = int.tryParse(mMatch?.group(1) ?? '0') ?? 0;
      return Duration(hours: h, minutes: m);
    }

    // Просто число => считаем минутами
    final numOnly = RegExp(r'^\d+$');
    if (numOnly.hasMatch(s)) {
      final mins = int.tryParse(s) ?? 0;
      return Duration(minutes: mins);
    }

    return null;
  }

  /// Формат «часы и минуты» в виде коротких меток.
  ///
  /// `locale`:
  /// - 'uk' → "год", "хв" (по умолчанию)
  /// - 'ru' → "ч", "мин"
  /// - 'en' → "h", "m"
  static String formatHm(String? raw, {String locale = 'uk'}) {
    final d = parse(raw);
    if (d == null) return '';

    final h = d.inHours;
    final m = d.inMinutes.remainder(60);

    String hLbl = 'год';
    String mLbl = 'хв';

    switch (locale) {
      case 'ru':
        hLbl = 'ч';
        mLbl = 'мин';
        break;
      case 'en':
        hLbl = 'h';
        mLbl = 'm';
        break;
      case 'uk':
      default:
        hLbl = 'год';
        mLbl = 'хв';
    }

    if (h <= 0) {
      return '$m $mLbl';
    }
    if (m <= 0) {
      return '$h $hLbl';
    }
    return '$h $hLbl $m $mLbl';
  }
}

/// Удобный алиас.
String formatBookDuration(String? raw, {String locale = 'uk'}) =>
    DurationFormat.formatHm(raw, locale: locale);
