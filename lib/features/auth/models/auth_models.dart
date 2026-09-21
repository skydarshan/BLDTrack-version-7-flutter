import 'user_model.dart';
import '../../../core/org/org_modules.dart';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.user,
    this.refreshToken,
  });

  final String accessToken;
  final String? refreshToken;
  final UserModel user;
}

class RegisterOrganizationRequest {
  RegisterOrganizationRequest({
    required this.organizationName,
    required this.subdomain,
    required this.adminName,
    required this.adminEmail,
    required this.adminPassword,
    required this.adminPhone,
    required this.modules,
    this.contactEmail,
    this.contactPhone,
    this.address,
    this.procurementConfig,
    this.projectManagementConfig,
  });

  final String organizationName;
  final String subdomain;
  final String adminName;
  final String adminEmail;
  final String adminPassword;
  final String adminPhone;
  final String? contactEmail;
  final String? contactPhone;
  final String? address;
  final Map<String, dynamic> modules;
  final Map<String, dynamic>? procurementConfig;
  final Map<String, dynamic>? projectManagementConfig;

  Map<String, dynamic> toJson() {
    final normalized = normalizeOrgModules(modules);
    final procurementOn = normalized['procurement'] is Map &&
        (normalized['procurement'] as Map)['enabled'] == true;
    final pmOn = normalized['project_management'] is Map &&
        (normalized['project_management'] as Map)['enabled'] == true;

    return {
      'organizationName': organizationName,
      'subdomain': subdomain,
      'adminName': adminName,
      'adminEmail': adminEmail,
      'adminPassword': adminPassword,
      'adminPhone': adminPhone,
      'contactEmail': contactEmail ?? adminEmail,
      if (contactPhone != null && contactPhone!.isNotEmpty) 'contactPhone': contactPhone,
      if (address != null && address!.isNotEmpty) 'address': address,
      'modules': normalized,
      if (procurementOn && procurementConfig != null)
        'procurement_config': procurementConfig,
      if (pmOn && projectManagementConfig != null)
        'project_management_config': projectManagementConfig,
    };
  }
}

/// Builds a subdomain from organization name (same as React frontend).
String buildSubdomain(String organizationName) {
  final base = organizationName
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  if (base.isEmpty) return 'orgapp';
  if (base.length >= 3) {
    return base.length > 63 ? base.substring(0, 63) : base;
  }
  final padded = '${base}org';
  return padded.length > 63 ? padded.substring(0, 63) : padded;
}
