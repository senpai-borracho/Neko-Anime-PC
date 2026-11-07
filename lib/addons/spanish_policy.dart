/// Política exclusiva de Complementos. No identifica idiomas a partir del título
/// de una obra ni de su URL; requiere datos del enlace o de una fuente monolingüe.
class SpanishPolicy {
  static bool spanish(dynamic value) {
    final text = '$value'.toLowerCase().replaceAll('_', '-');
    return RegExp(
          r'(^|[^a-z])(es(?:-[a-z0-9]+)?|spa|esp|spanish|español|espanol|castellano|latino|latam|vose)([^a-z]|$)',
        ).hasMatch(text) ||
        text.contains('🇪🇸') ||
        text.contains('🇲🇽') ||
        text.contains('🇦🇷') ||
        text.contains('🇨🇱') ||
        text.contains('🇨🇴') ||
        const ['🇧🇴','🇵🇪','🇪🇨','🇻🇪','🇺🇾','🇵🇾','🇨🇷','🇨🇺','🇩🇴','🇬🇹','🇭🇳','🇳🇮','🇵🇦','🇵🇷','🇸🇻']
            .any(text.contains);
  }

  static bool onlySpanish(dynamic values) {
    final list = values is List ? values : [values];
    return list.isNotEmpty && list.every(spanish);
  }

  static List<Map<String, dynamic>> subtitles(Map data) {
    final raw = data['subtitles'];
    if (raw is! List) return [];
    return [
      for (final s in raw.whereType<Map>())
        if (spanish(s['lang'] ?? s['language'] ?? s['label'] ?? s['title']) &&
            ['https', 'http'].contains(Uri.tryParse('${s['url']}')?.scheme))
          Map<String, dynamic>.from(s),
    ];
  }

  static bool allows(Map data, {bool trustedSpanish = false}) {
    if (subtitles(data).isNotEmpty) return true;
    final languages = [
      for (final key in const [
        'language',
        'languages',
        'lang',
        'audioLanguage',
        'audioLanguages',
        'subtitleLanguage',
        'subtitleLanguages',
      ])
        if (data[key] != null) data[key],
    ];
    if (languages.isNotEmpty) {
      return languages.any(
        (value) => value is List ? value.any(spanish) : spanish(value),
      );
    }
    final labels = [
      data['name'],
      data['title'],
      data['description'],
      data['label'],
    ].whereType<String>().join(' ');
    if (spanish(labels)) return true;
    // Una etiqueta explícita de otro idioma prevalece sobre el idioma del proveedor.
    if (RegExp(
      r'\b(english|eng|en|french|fre|fr|german|ger|de|portuguese|por|pt)\b',
      caseSensitive: false,
    ).hasMatch(labels)) {
      return false;
    }
    return trustedSpanish;
  }
}
