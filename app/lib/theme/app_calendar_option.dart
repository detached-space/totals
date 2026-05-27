enum AppCalendarOption {
  gregorian(
    storageValue: 'gregorian',
    label: 'Gregorian Calendar (GC)',
  ),
  ethiopian(
    storageValue: 'ethiopian',
    label: 'Ethiopian Calendar (EC)',
  );

  const AppCalendarOption({
    required this.storageValue,
    required this.label,
  });

  final String storageValue;
  final String label;

  static AppCalendarOption fromStorage(String? value) {
    for (final option in AppCalendarOption.values) {
      if (option.storageValue == value) {
        return option;
      }
    }
    return AppCalendarOption.gregorian;
  }
}
