import 'package:flutter/material.dart';
import 'tax_status_panel.dart';

class DriverTaxInformationPage extends StatelessWidget {
  const DriverTaxInformationPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Налоги и чеки')),
      body: const SingleChildScrollView(
          padding: EdgeInsets.all(16), child: TaxStatusPanel(driver: true)));
}
