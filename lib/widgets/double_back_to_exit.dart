class DoubleBackToExit extends StatelessWidget {
  final Widget child;
  final Duration interval;
  final String message;

  const DoubleBackToExit({
    super.key,
    required this.child,
    this.interval = const Duration(seconds: 2),
    this.message = 'Натисніть ще раз, щоб вийти',
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
