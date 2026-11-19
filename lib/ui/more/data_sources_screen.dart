// Data sources & licenses: attribution for the bundled food datasets.
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

import '../../theme.dart';

class DataSourcesScreen extends StatelessWidget {
  const DataSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Data sources & licenses')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _block(
              'Open Food Facts',
              'This app contains information from Open Food Facts '
                  '(https://world.openfoodfacts.org), which is made available '
                  'here under the Open Database License (ODbL) 1.0 '
                  '(https://opendatacommons.org/licenses/odbl/1-0). '
                  '© Open Food Facts contributors.\n\n'
                  'The bundled product database (foods_off.db) is a derivative '
                  'of the Open Food Facts database (filtered to products with a '
                  'name and normalized nutrient fields) and is therefore '
                  'licensed under the ODbL 1.0 as well. If you redistribute it '
                  'or a further derivative, it must remain under the ODbL and '
                  'keep this attribution. Product images are not redistributed '
                  'by this app.',
              'https://world.openfoodfacts.org/terms-of-use',
            ),
            const SizedBox(height: 16),
            _block(
              'USDA FoodData Central',
              'The common-foods database (foods_common.db) is built from USDA '
                  'FoodData Central: FNDDS 2021-2023 and SR Legacy (April 2018). '
                  'USDA FoodData Central data are in the public domain, '
                  'published under CC0 1.0 Universal.\n\n'
                  'Suggested citation: U.S. Department of Agriculture, '
                  'Agricultural Research Service. FoodData Central. '
                  'fdc.nal.usda.gov.',
              'https://fdc.nal.usda.gov/',
            ),
            const SizedBox(height: 16),
            const Text(
              'This app is not affiliated with or endorsed by Open Food Facts '
              'or the USDA. Application code is a private project.',
              style: TextStyle(color: MtTheme.textDim, fontSize: 12),
            ),
          ],
        ),
      );

  Widget _block(String title, String body, String url) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: MtTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 8),
            Text(url, style: const TextStyle(color: MtTheme.accent, fontSize: 12)),
          ],
        ),
      );
}
