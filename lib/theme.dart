import 'package:flutter/material.dart';

final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  scaffoldBackgroundColor: Color(0xFFFFFFFF), // Beyaz arka plan
  appBarTheme: AppBarTheme(
    backgroundColor: Color(0xFF6A0DAD), // Zengin mor ton (appbar için)
    foregroundColor: Colors.white,
    elevation: 0,
  ),
  colorScheme: const ColorScheme.light(
    primary: Color(0xFF6A0DAD), // Mor (ana renk)
    onPrimary: Colors.white, // Mor üzeri yazı
    secondary: Color(0xFFB388EB), // Açık mor (ikincil)
    onSecondary: Colors.black, // Açık mor üzeri yazı
    background: Color(0xFFFFFFFF), // Genel arka plan (beyaz)
    onBackground: Colors.black, // Arka plan üzeri yazı
    surface: Color(0xFFF3F0FF), // Hafif lavanta (kartlar vs)
    onSurface: Colors.deepPurple, // Kart üzeri yazı
    error: Colors.red,
    onError: Colors.white,
  ),
  cardColor: Color(0xFFF3F0FF), // Yumuşak lavanta kartlar için
  textTheme: Typography.blackCupertino,
  useMaterial3: true,
);

final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: Color(0xFF0F172A), // gece mavisi
  appBarTheme: AppBarTheme(
    backgroundColor: Color(0xFF1E293B), // koyu gece mavisi
    foregroundColor: Colors.white,
    elevation: 0,
  ),
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF38BDF8), // camgöbeği
    onPrimary: Colors.black,
    secondary: Color(0xFF7C3AED), // sisli mor
    onSecondary: Colors.white,
    background: Color(0xFF0F172A),
    onBackground: Colors.white,
    surface: Color(0xFF1E293B), // koyu gece yüzeyi
    onSurface: Colors.white70,
    error: Colors.redAccent,
    onError: Colors.black,
  ),
  cardColor: Color(0xFF1E293B),
  textTheme: Typography.whiteCupertino,
  useMaterial3: true,
);
