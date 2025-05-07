import 'package:flutter/material.dart';

class AuthPage extends StatelessWidget {
  final void Function() onAuthenticate;
  const AuthPage({super.key, required this.onAuthenticate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Scaffold(
      body: Stack(
        children: [
          Center(
            child: Image.asset(
              'assets/images/bg.png',
              fit: BoxFit.cover,
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Center(
                  child: Image.asset(
                    'assets/images/logo-text-white.png',
                    fit: BoxFit.cover,
                    width: 250,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'HOME FOR ALL YOUR ACCOUNTS',
                  style: TextStyle(
                    fontSize: 14,
                    // fontWeight: FontWeight.bold,
                    color: Colors.grey[300],
                  ),
                ),
                SizedBox(height: 20),
                FloatingActionButton(
                  onPressed: onAuthenticate,
                  child: const Icon(Icons.lock_open),
                )
              ],
            ),
          ),
        ],
      ),
    ));
  }
}
