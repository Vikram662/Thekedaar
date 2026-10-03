import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/db/enums.dart';
import '../core/utils/dates.dart';
import '../features/attendance/presentation/daily_attendance_screen.dart';
import '../features/backup/presentation/backup_screen.dart';
import '../features/backup/presentation/restore_screen.dart';
import '../features/billing/presentation/billing_screen.dart';
import '../features/billing/presentation/client_detail_screen.dart';
import '../features/billing/presentation/client_form_screen.dart';
import '../features/billing/presentation/document_detail_screen.dart';
import '../features/billing/presentation/document_editor_screen.dart';
import '../features/billing/presentation/payment_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/khata/presentation/khata_screen.dart';
import '../features/khata/presentation/ledger_entry_screen.dart';
import '../features/khata/presentation/piece_work_screen.dart';
import '../features/khata/presentation/settlement_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/settings/presentation/app_lock_settings_screen.dart';
import '../features/settings/presentation/business_profile_screen.dart';
import '../features/settings/presentation/rules_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/trades_screen.dart';
import '../features/workers/presentation/change_wage_screen.dart';
import '../features/workers/presentation/worker_detail_screen.dart';
import '../features/workers/presentation/worker_form_screen.dart';
import '../features/workers/presentation/workers_screen.dart';
import 'home_shell.dart';

abstract final class Routes {
  static const onboarding = '/onboarding';
  static const restore = '/restore';

  // Bottom tabs (PRD E1)
  static const dashboard = '/';
  static const billing = '/billing';
  static const khata = '/khata';
  static const workers = '/workers';

  static const addWorker = '/worker/new';
  static String worker(String id) => '/worker/$id';
  static String editWorker(String id) => '/worker/$id/edit';
  static String changeWage(String id) => '/worker/$id/wage';

  static String attendance([DateTime? date]) =>
      date == null ? '/attendance' : '/attendance?date=${isoDate(date)}';

  static String ledgerEntry({String? workerId, LedgerType? type}) {
    final query = [
      if (workerId != null) 'workerId=$workerId',
      if (type != null) 'type=${type.name}',
    ].join('&');
    return query.isEmpty ? '/khata/entry' : '/khata/entry?$query';
  }

  static String pieceWork([String? workerId]) =>
      workerId == null ? '/khata/piece' : '/khata/piece?workerId=$workerId';
  static String settle(String workerId) => '/khata/settle/$workerId';

  static String newDocument(DocumentKind kind, {String? clientId}) =>
      '/doc/new?kind=${kind.name}${clientId == null ? '' : '&clientId=$clientId'}';
  static String document(String id) => '/doc/$id';
  static String editDocument(String id) => '/doc/$id/edit';

  static const addClient = '/client/new';
  static String client(String id) => '/client/$id';
  static String editClient(String id) => '/client/$id/edit';

  static String payment({String? clientId, String? documentId}) {
    final query = [
      if (clientId != null) 'clientId=$clientId',
      if (documentId != null) 'documentId=$documentId',
    ].join('&');
    return query.isEmpty ? '/payment/new' : '/payment/new?$query';
  }

  static const settings = '/settings';
  static const businessProfile = '/settings/business';
  static const rules = '/settings/rules';
  static const trades = '/settings/trades';
  static const backup = '/settings/backup';
  static const appLock = '/settings/lock';
}

GoRouter buildRouter({required String initialLocation}) {
  String? q(GoRouterState state, String key) =>
      state.uri.queryParameters[key];
  String id(GoRouterState state) => state.pathParameters['id']!;

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.restore,
        builder: (context, state) => const RestoreScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (context, state) => const DashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.billing,
              builder: (context, state) => const BillingScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.khata,
              builder: (context, state) => const KhataScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.workers,
              builder: (context, state) => const WorkersScreen(),
            ),
          ]),
        ],
      ),
      // Full-screen pages above the tabs.
      GoRoute(
        path: Routes.addWorker,
        builder: (context, state) => const WorkerFormScreen(),
      ),
      GoRoute(
        path: '/worker/:id',
        builder: (context, state) => WorkerDetailScreen(workerId: id(state)),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                WorkerFormScreen(workerId: id(state)),
          ),
          GoRoute(
            path: 'wage',
            builder: (context, state) =>
                ChangeWageScreen(workerId: id(state)),
          ),
        ],
      ),
      GoRoute(
        path: '/attendance',
        builder: (context, state) {
          final date = q(state, 'date');
          return DailyAttendanceScreen(
            initialDate: date == null ? null : parseIsoDate(date),
          );
        },
      ),
      GoRoute(
        path: '/khata/entry',
        builder: (context, state) {
          final type = q(state, 'type');
          return LedgerEntryScreen(
            workerId: q(state, 'workerId'),
            type: type == null ? LedgerType.advance : LedgerType.values.byName(type),
          );
        },
      ),
      GoRoute(
        path: '/khata/piece',
        builder: (context, state) =>
            PieceWorkScreen(workerId: q(state, 'workerId')),
      ),
      GoRoute(
        path: '/khata/settle/:id',
        builder: (context, state) => SettlementScreen(workerId: id(state)),
      ),
      GoRoute(
        path: '/doc/new',
        builder: (context, state) => DocumentEditorScreen(
          kind: DocumentKind.values.byName(q(state, 'kind') ?? 'invoice'),
          clientId: q(state, 'clientId'),
        ),
      ),
      GoRoute(
        path: '/doc/:id',
        builder: (context, state) => DocumentDetailScreen(documentId: id(state)),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) => DocumentEditorScreen(
              kind: DocumentKind.invoice,
              documentId: id(state),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.addClient,
        builder: (context, state) => const ClientFormScreen(),
      ),
      GoRoute(
        path: '/client/:id',
        builder: (context, state) => ClientDetailScreen(clientId: id(state)),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) => ClientFormScreen(clientId: id(state)),
          ),
        ],
      ),
      GoRoute(
        path: '/payment/new',
        builder: (context, state) => PaymentScreen(
          clientId: q(state, 'clientId'),
          documentId: q(state, 'documentId'),
        ),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'business',
            builder: (context, state) => const BusinessProfileScreen(),
          ),
          GoRoute(
            path: 'rules',
            builder: (context, state) => const RulesScreen(),
          ),
          GoRoute(
            path: 'trades',
            builder: (context, state) => const TradesScreen(),
          ),
          GoRoute(
            path: 'backup',
            builder: (context, state) => const BackupScreen(),
          ),
          GoRoute(
            path: 'lock',
            builder: (context, state) => const AppLockSettingsScreen(),
          ),
        ],
      ),
    ],
  );
}

/// Shared "not found" body for detail pages whose record disappeared.
class NotFoundBody extends StatelessWidget {
  const NotFoundBody({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('This record was not found.'));
}
