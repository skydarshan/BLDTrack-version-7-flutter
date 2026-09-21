import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_apis.dart';
import 'master_crud_screen.dart';

class LocationsScreen extends StatelessWidget {
  const LocationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MasterCrudScreen(
      title: 'Locations',
      permission: 'location',
      api: context.read<SettingsApis>().locations,
      titleOf: (r) => r['location_name']?.toString() ?? 'Location',
      sortBy: 'location_name',
      fields: const [
        MasterFieldDef(key: 'location_name', label: 'Location name', required: true),
      ],
    );
  }
}

class ActivitiesScreen extends StatelessWidget {
  const ActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MasterCrudScreen(
      title: 'Activities',
      permission: 'activity',
      api: context.read<SettingsApis>().activities,
      titleOf: (r) => r['activity_name']?.toString() ?? 'Activity',
      sortBy: 'activity_name',
      fields: const [
        MasterFieldDef(key: 'activity_name', label: 'Activity name', required: true),
      ],
    );
  }
}

class SubActivitiesScreen extends StatelessWidget {
  const SubActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MasterCrudScreen(
      title: 'Sub Activities',
      permission: 'subactivity',
      api: context.read<SettingsApis>().subActivities,
      titleOf: (r) => r['sub_activity_name']?.toString() ?? 'Sub activity',
      sortBy: 'sub_activity_name',
      fields: const [
        MasterFieldDef(
          key: 'sub_activity_name',
          label: 'Sub activity name',
          required: true,
        ),
      ],
    );
  }
}

class UomsScreen extends StatelessWidget {
  const UomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MasterCrudScreen(
      title: 'UOMs',
      permission: 'uom',
      api: context.read<SettingsApis>().uoms,
      titleOf: (r) => r['uom_name']?.toString() ?? 'UOM',
      subtitleOf: (r) => r['unit']?.toString() ?? '',
      sortBy: 'uom_name',
      fields: const [
        MasterFieldDef(key: 'uom_name', label: 'UOM name', required: true),
        MasterFieldDef(key: 'unit', label: 'Unit', required: true),
      ],
    );
  }
}

class GstsScreen extends StatelessWidget {
  const GstsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MasterCrudScreen(
      title: 'GST',
      permission: 'gst',
      api: context.read<SettingsApis>().gsts,
      titleOf: (r) => r['gst_name']?.toString() ?? 'GST',
      subtitleOf: (r) => '${r['gst_percentage'] ?? ''}%',
      sortBy: 'gst_name',
      fields: const [
        MasterFieldDef(key: 'gst_name', label: 'GST name', required: true),
        MasterFieldDef(
          key: 'gst_percentage',
          label: 'Percentage',
          required: true,
          keyboardType: TextInputType.number,
        ),
      ],
      buildPayload: (c, _) => {
        'gst_name': c['gst_name']!.text.trim(),
        'gst_percentage': num.tryParse(c['gst_percentage']!.text.trim()) ?? 0,
      },
    );
  }
}

class BrandsScreen extends StatelessWidget {
  const BrandsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MasterCrudScreen(
      title: 'Brands',
      permission: 'brand',
      api: context.read<SettingsApis>().brands,
      titleOf: (r) => r['brand_name']?.toString() ?? 'Brand',
      sortBy: 'brand_name',
      fields: const [
        MasterFieldDef(key: 'brand_name', label: 'Brand name', required: true),
      ],
    );
  }
}

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MasterCrudScreen(
      title: 'Categories',
      permission: 'category',
      api: context.read<SettingsApis>().categories,
      titleOf: (r) => r['name']?.toString() ?? 'Category',
      subtitleOf: (r) => '${r['code'] ?? ''} · ${r['type'] ?? ''}',
      sortBy: 'name',
      fields: const [
        MasterFieldDef(key: 'name', label: 'Name', required: true),
        MasterFieldDef(key: 'code', label: 'Code', required: true),
        MasterFieldDef(key: 'type', label: 'Type', required: true),
      ],
      extraFormBuilder: (context, controllers, extras, setLocal) {
        final type = controllers['type']!.text.isEmpty
            ? 'Project Site Purchase'
            : controllers['type']!.text;
        return DropdownButtonFormField<String>(
          initialValue: type == 'Plant & Machinery'
              ? 'Plant & Machinery'
              : 'Project Site Purchase',
          decoration: const InputDecoration(labelText: 'Type *'),
          items: const [
            DropdownMenuItem(
              value: 'Project Site Purchase',
              child: Text('Project Site Purchase'),
            ),
            DropdownMenuItem(
              value: 'Plant & Machinery',
              child: Text('Plant & Machinery'),
            ),
          ],
          onChanged: (v) {
            controllers['type']!.text = v ?? 'Project Site Purchase';
            setLocal(() {});
          },
        );
      },
    );
  }
}

class MiscConfigsScreen extends StatelessWidget {
  const MiscConfigsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MasterCrudScreen(
      title: 'Misc Configs',
      permission: 'miscellaneousconfig',
      api: context.read<SettingsApis>().miscConfigs,
      titleOf: (r) => r['type']?.toString() ?? 'Config',
      subtitleOf: (r) => r['value']?.toString() ?? '',
      fields: const [
        MasterFieldDef(key: 'type', label: 'Type', required: true),
        MasterFieldDef(key: 'value', label: 'Value', required: true, maxLines: 3),
      ],
    );
  }
}
