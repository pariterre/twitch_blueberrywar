import 'package:flutter/material.dart';
import 'package:twitch_blueberry_war/screens/blueberry_war_game_screen.dart';
import 'package:twitch_blueberry_war/to_remove/any_dumb_stuff.dart';

void main() {
  Managers.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: Scaffold(body: BlueberryWarGameScreen()),
    );
  }
}
