// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';

import 'clients/admin_client.dart';
import 'clients/core_client.dart';
import 'clients/products_client.dart';
import 'clients/audit_client.dart';
import 'clients/crm_client.dart';
import 'clients/engineering_client.dart';
import 'clients/production_client.dart';
import 'clients/configurator_client.dart';
import 'clients/helpdesk_client.dart';
import 'clients/reports_client.dart';
import 'clients/delivery_client.dart';
import 'clients/repairs_client.dart';
import 'clients/favorites_client.dart';
import 'clients/field_client.dart';
import 'clients/finance_client.dart';
import 'clients/purchasing_client.dart';
import 'clients/imports_client.dart';
import 'clients/inventory_client.dart';
import 'clients/kb_client.dart';
import 'clients/sales_client.dart';
import 'clients/planning_client.dart';
import 'clients/portal_client.dart';
import 'clients/todo_client.dart';

/// tradocraft API `v0.1.0`.
///
/// Business platform API (CRM, products, pricing, sales, engineering, helpdesk, customer portal).
class TradocraftApi {
  TradocraftApi(
    Dio dio, {
    String? baseUrl,
  })  : _dio = dio,
        _baseUrl = baseUrl;

  final Dio _dio;
  final String? _baseUrl;

  static String get version => '0.1.0';

  AdminClient? _admin;
  CoreClient? _core;
  ProductsClient? _products;
  AuditClient? _audit;
  CrmClient? _crm;
  EngineeringClient? _engineering;
  ProductionClient? _production;
  ConfiguratorClient? _configurator;
  HelpdeskClient? _helpdesk;
  ReportsClient? _reports;
  DeliveryClient? _delivery;
  RepairsClient? _repairs;
  FavoritesClient? _favorites;
  FieldClient? _field;
  FinanceClient? _finance;
  PurchasingClient? _purchasing;
  ImportsClient? _imports;
  InventoryClient? _inventory;
  KbClient? _kb;
  SalesClient? _sales;
  PlanningClient? _planning;
  PortalClient? _portal;
  TodoClient? _todo;

  AdminClient get admin => _admin ??= AdminClient(_dio, baseUrl: _baseUrl);

  CoreClient get core => _core ??= CoreClient(_dio, baseUrl: _baseUrl);

  ProductsClient get products => _products ??= ProductsClient(_dio, baseUrl: _baseUrl);

  AuditClient get audit => _audit ??= AuditClient(_dio, baseUrl: _baseUrl);

  CrmClient get crm => _crm ??= CrmClient(_dio, baseUrl: _baseUrl);

  EngineeringClient get engineering => _engineering ??= EngineeringClient(_dio, baseUrl: _baseUrl);

  ProductionClient get production => _production ??= ProductionClient(_dio, baseUrl: _baseUrl);

  ConfiguratorClient get configurator => _configurator ??= ConfiguratorClient(_dio, baseUrl: _baseUrl);

  HelpdeskClient get helpdesk => _helpdesk ??= HelpdeskClient(_dio, baseUrl: _baseUrl);

  ReportsClient get reports => _reports ??= ReportsClient(_dio, baseUrl: _baseUrl);

  DeliveryClient get delivery => _delivery ??= DeliveryClient(_dio, baseUrl: _baseUrl);

  RepairsClient get repairs => _repairs ??= RepairsClient(_dio, baseUrl: _baseUrl);

  FavoritesClient get favorites => _favorites ??= FavoritesClient(_dio, baseUrl: _baseUrl);

  FieldClient get field => _field ??= FieldClient(_dio, baseUrl: _baseUrl);

  FinanceClient get finance => _finance ??= FinanceClient(_dio, baseUrl: _baseUrl);

  PurchasingClient get purchasing => _purchasing ??= PurchasingClient(_dio, baseUrl: _baseUrl);

  ImportsClient get imports => _imports ??= ImportsClient(_dio, baseUrl: _baseUrl);

  InventoryClient get inventory => _inventory ??= InventoryClient(_dio, baseUrl: _baseUrl);

  KbClient get kb => _kb ??= KbClient(_dio, baseUrl: _baseUrl);

  SalesClient get sales => _sales ??= SalesClient(_dio, baseUrl: _baseUrl);

  PlanningClient get planning => _planning ??= PlanningClient(_dio, baseUrl: _baseUrl);

  PortalClient get portal => _portal ??= PortalClient(_dio, baseUrl: _baseUrl);

  TodoClient get todo => _todo ??= TodoClient(_dio, baseUrl: _baseUrl);
}
