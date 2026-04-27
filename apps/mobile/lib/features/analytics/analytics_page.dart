import 'package:flutter/material.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('分析')),
      body: const Center(child: Text('组合分析 (FIR-7) + 收益率 (FIR-8) — 待实现')),
    );
  }
}
