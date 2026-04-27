import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.account_circle_outlined),
            title: Text('账户'),
            subtitle: Text('登录与多端同步 (FIR-27 / FIR-28)'),
          ),
          ListTile(
            leading: Icon(Icons.currency_exchange),
            title: Text('基础货币'),
            subtitle: Text('CNY (默认)'),
          ),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于 NaviWealth'),
            subtitle: Text('v0.1.0'),
          ),
        ],
      ),
    );
  }
}
