import 'package:flutter/material.dart';

class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('资产')),
      body: const Center(child: Text('资产录入与管理 (FIR-5) — 待实现')),
      floatingActionButton: const FloatingActionButton.extended(
        onPressed: null,
        icon: Icon(Icons.add),
        label: Text('添加资产'),
      ),
    );
  }
}
