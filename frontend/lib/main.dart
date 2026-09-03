import 'package:flutter/material.dart';

import 'screens/home/home_screen.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';
import 'widgets/review_action_card.dart';

void main() {
  runApp(ChangaSmartApp(api: ApiService()));
}

class ChangaSmartApp extends StatelessWidget {
  final ApiService api;

  const ChangaSmartApp({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return ApiServiceProvider(
      api: api,
      child: MaterialApp(
        title: 'ChangaSmart',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: HomeScreen(api: api),
      ),
    );
  }
}
