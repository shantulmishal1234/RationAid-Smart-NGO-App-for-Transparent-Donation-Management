import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ration_aid/providers/theme_provider.dart';

void main() {
  // ThemeProvider uses SharedPreferences so we need to initialize a fake instance
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeProvider', () {
    test('initial theme mode defaults to system', () async {
      final provider = ThemeProvider();
      // Give async _loadThemeMode time to complete
      await Future.delayed(const Duration(milliseconds: 100));
      expect(provider.themeMode, ThemeMode.system);
    });

    test('isDarkMode is false when in system/light mode', () async {
      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 100));
      expect(provider.isDarkMode, false);
    });

    test('setThemeMode(dark) updates themeMode and persists to SharedPreferences', () async {
      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.setThemeMode(ThemeMode.dark);

      expect(provider.themeMode, ThemeMode.dark);
      expect(provider.isDarkMode, true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');
    });

    test('setThemeMode(light) updates themeMode and persists to SharedPreferences', () async {
      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.setThemeMode(ThemeMode.light);

      expect(provider.themeMode, ThemeMode.light);
      expect(provider.isDarkMode, false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'light');
    });

    test('setThemeMode(system) persists "system" to SharedPreferences', () async {
      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.setThemeMode(ThemeMode.system);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'system');
    });

    test('toggleTheme switches from light to dark', () async {
      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.setThemeMode(ThemeMode.light);
      await provider.toggleTheme();

      expect(provider.themeMode, ThemeMode.dark);
    });

    test('toggleTheme switches from dark to light', () async {
      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      await provider.setThemeMode(ThemeMode.dark);
      await provider.toggleTheme();

      expect(provider.themeMode, ThemeMode.light);
    });

    test('toggleTheme from system mode goes to dark', () async {
      // When not in dark mode (system or light), toggle goes dark
      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      // Default is system (not dark)
      await provider.toggleTheme();
      expect(provider.themeMode, ThemeMode.dark);
    });

    test('ThemeProvider extends ChangeNotifier and fires notifications', () async {
      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      await provider.setThemeMode(ThemeMode.dark);
      expect(notifyCount, greaterThan(0));
    });

    test('ThemeProvider loads persisted theme on construction', () async {
      // Set a pre-existing preference
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});

      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(provider.themeMode, ThemeMode.dark);
      expect(provider.isDarkMode, true);
    });

    test('ThemeProvider loads persisted "light" theme on construction', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'light'});

      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(provider.themeMode, ThemeMode.light);
      expect(provider.isDarkMode, false);
    });

    test('ThemeProvider defaults to system for unknown persisted value', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'unknown_value'});

      final provider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(provider.themeMode, ThemeMode.system);
    });
  });
}
