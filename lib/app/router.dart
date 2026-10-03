import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/db/enums.dart';
import '../core/utils/dates.dart';
import '../features/attendance/presentation/attendance_screen.dart';
import '../features/backup/presentation/backup_screen.dart';
import '../features/backup/presentation/restore_screen.dart';
import '../features/billing/presentation/billing_screen.dart';
import '../features/billing/presentation/client_detail_screen.dart';
import '../features/billing/presentation/client_form_screen.dart';
import '../features/billing/presentation/document_detail_screen.dart';
import '../features/billing/presentation/document_editor_screen.dart';
import '../features/billing/presentation/payment_screen.dart';
import '../features/calendar/presentation/calendar_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/expenses/presentation/expense_entry_screen.dart';
import '../features/expenses/presentation/expenses_screen.dart';
import '../features/expenses/presentation/suppliers_screen.dart';
import '../features/jobs/presentation/jobs_screens.dart';
import '../features/khata/presentation/khata_screen.dart';
import '../features/khata/presentation/ledger_entry_screen.dart';
import '../features/khata/presentation/piece_work_screen.dart';
import '../features/khata/presentation/settlement_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/reports/presentation/dues_screen.dart';
import '../features/settings/presentation/app_lock_settings_screen.dart';
import '../features/settings/presentation/business_profile_screen.dart';
import '../features/settings/presentation/reminders_screen.dart';
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

  /// Billing tab on a sub-tab: 0 bills, 1 quotations, 2 clients, 3 payments.
  static String billingTab(int tab) => '/billing?tab=$tab';

  /// Khata tab on a sub-tab: 0 balances, 1 entries.
  static String khataTab(int tab) => '/khata?tab=$tab';

  static const addWorker = '/worker/new';
  static String worker(String id) => '/worker/$id';
  static String editWorker(String id) => '/worker/$id/edit';
  static String changeWage(String id) => '/worker/$id/wage';

  /// Attendance tab, "Mark today" view (optionally for [date]).
  static String attendance([DateTime? date]) =>
      date == null ? '/attendance' : '/attendance?date=${isoDate(date)}';

  /// Attendance tab, all-workers month register.
  static const attendanceMonth = '/attendance?view=month';

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

  static String newDocument(DocumentKind kind, {String? clientId, String? jobId}) =>
      '/doc/new?kind=${kind.name}'
      '${clientId == null ? '' : '&clientId=$clientId'}'
      '${jobId == null ? '' : '&jobId=$jobId'}';
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

  static const expenses = '/expenses';
  static const addExpense = '/expenses/new';
  static String expenseForJob(String jobId) => '/expenses/new?jobId=$jobId';
  static const jobs = '/jobs';
  static String addJob({String? clientId}) =>
      clientId == null ? '/job/new' : '/job/new?clientId=$clientId';
  static String job(String id) => '/job/$id';
  static String editJob(String id) => '/job/$id/edit';
  static const suppliers = '/suppliers';
  static const addSupplier = '/supplier/new';
  static String supplier(String id) => '/supplier/$id';
  static String editSupplier(String id) => '/supplier/$id/edit';
  static String supplierEntry(String id, SupplierEntryType type) =>
      '/supplier/$id/entry?type=${type.name}';

  /// Lena / Dena report; tab 0 = to receive, 1 = to pay.
  static String dues([int tab = 0]) => '/dues?tab=$tab';
  static const calendar = '/calendar';

  static const settings = '/settings';
  static const businessProfile = '/settings/business';
  static const rules = '/settings/rules';
  static const trades = '/settings/trades';
  static const backup = '/settings/backup';
  static const appLock = '/settings/lock';
  static const reminders = '/settings/reminders';
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
              path: '/attendance',
              builder: (context, state) {
                final date = q(state, 'date');
                return AttendanceScreen(
                  date: date == null ? null : parseIsoDate(date),
                  showMonth: q(state, 'view') == 'month',
                );
              },
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.billing,
              builder: (context, state) => BillingScreen(
                tab: int.tryParse(q(state, 'tab') ?? ''),
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.khata,
              builder: (context, state) => KhataScreen(
                tab: int.tryParse(q(state, 'tab') ?? ''),
              ),
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
          jobId: q(state, 'jobId'),
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
        path: Routes.expenses,
        builder: (context, state) => const ExpensesScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) =>
                ExpenseEntryScreen(jobId: q(state, 'jobId')),
          ),
        ],
      ),
      GoRoute(
        path: Routes.jobs,
        builder: (context, state) => const JobsScreen(),
      ),
      GoRoute(
        path: '/job/new',
        builder: (context, state) =>
            JobFormScreen(clientId: q(state, 'clientId')),
      ),
      GoRoute(
        path: '/job/:id',
        builder: (context, state) => JobDetailScreen(jobId: id(state)),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) => JobFormScreen(jobId: id(state)),
          ),
        ],
      ),
      GoRoute(
        path: Routes.suppliers,
        builder: (context, state) => const SuppliersScreen(),
      ),
      GoRoute(
        path: Routes.addSupplier,
        builder: (context, state) => const SupplierFormScreen(),
      ),
      GoRoute(
        path: '/supplier/:id',
        builder: (context, state) =>
            SupplierDetailScreen(supplierId: id(state)),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                SupplierFormScreen(supplierId: id(state)),
          ),
          GoRoute(
            path: 'entry',
            builder: (context, state) => SupplierEntryScreen(
              supplierId: id(state),
              type: q(state, 'type') == SupplierEntryType.payment.name
                  ? SupplierEntryType.payment
                  : SupplierEntryType.purchase,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/dues',
        builder: (context, state) => DuesScreen(
          initialTab: int.tryParse(q(state, 'tab') ?? '') == 1 ? 1 : 0,
        ),
      ),
      GoRoute(
        path: Routes.calendar,
        builder: (context, state) => const CalendarScreen(),
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
          GoRoute(
            path: 'reminders',
            builder: (context, state) => const RemindersScreen(),
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
