/// API base URL, provided at build/run time via --dart-define.
///
/// Never hard-code "localhost" here: on a physical Android device,
/// "localhost" means the phone itself, not your development computer.
/// Run with:
///
///   flutter run --dart-define=API_BASE_URL=http://YOUR_COMPUTER_IP:8000
///
/// See frontend/README.md for how to find YOUR_COMPUTER_IP and for the
/// Android emulator special case (10.0.2.2).
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
}
