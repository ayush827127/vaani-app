import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLangKey = 'language';

final localeProvider =
    StateNotifierProvider<LocaleNotifier, Locale>((ref) => LocaleNotifier());

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en')) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString(_kLangKey) ?? 'English';
    state = _toLocale(lang);
  }

  Future<void> setLanguage(String langName) async {
    state = _toLocale(langName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangKey, langName);
  }

  static Locale _toLocale(String langName) =>
      langName == 'Hindi' ? const Locale('hi') : const Locale('en');

  String get currentLanguage =>
      state.languageCode == 'hi' ? 'Hindi' : 'English';
}
