import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/backup/clock_check.dart';
import 'package:thekedaar/core/db/database.dart';
import 'package:thekedaar/core/db/enums.dart';
import 'package:thekedaar/core/notify/notifications.dart';
import 'package:thekedaar/core/notify/reminders.dart';
import 'package:thekedaar/core/settings/app_settings.dart';
import 'package:thekedaar/core/utils/upi.dart';
import 'package:thekedaar/features/billing/data/billing_repository.dart';
import 'package:thekedaar/features/workers/data/workers_repository.dart';

void main() {
  group('UPI link (KH-08, BL-11)', () {
    test('builds a upi:// link with amount in rupees', () {
      expect(
        upiPayUri(
          upiId: 'ramesh@okaxis',
          payeeName: 'Ramesh Electric',
          amountPaise: 1250050,
          note: 'INV/26-27/0001',
        ),
        'upi://pay?pa=ramesh%40okaxis&pn=Ramesh%20Electric&am=12500.50'
        '&cu=INR&tn=INV%2F26-27%2F0001',
      );
      expect(
        upiPayUri(upiId: 'a@ybl', payeeName: 'A', amountPaise: 60000),
        contains('am=600.00'),
      );
      expect(
        upiPayUri(upiId: 'a@ybl', payeeName: 'A'),
        isNot(contains('am=')),
      );
    });

    test('validates UPI ids', () {
      expect(isValidUpiId('ramesh.electric@okaxis'), isTrue);
      expect(isValidUpiId(' 9876543210@ybl '), isTrue);
      expect(isValidUpiId('ramesh'), isFalse);
      expect(isValidUpiId('@okaxis'), isFalse);
      expect(isValidUpiId('a b@okaxis'), isFalse);
    });
  });

  group('Drive clock check (I-M12)', () {
    final server = DateTime.utc(2026, 10, 3, 12);

    test('small differences are ignored', () {
      expect(
        significantClockSkew(
            server: server, phone: server.add(const Duration(minutes: 9))),
        isNull,
      );
    });

    test('phone behind or ahead by more than 10 minutes is reported', () {
      final behind = significantClockSkew(
          server: server, phone: server.subtract(const Duration(hours: 2)));
      expect(behind, const Duration(hours: 2));
      expect(describeClockSkew(behind!), '2 hours behind');

      final ahead = significantClockSkew(
          server: server, phone: server.add(const Duration(days: 3)));
      expect(describeClockSkew(ahead!), '3 days ahead');
      expect(describeClockSkew(const Duration(minutes: 75)),
          '1 hour 15 min behind');
    });
  });

  group('reminder rules (DB-07)', () {
    const all = ReminderSettings();
    final midMonth = DateTime(2026, 10, 15, 10);

    Set<NotificationKind> kinds(List<Reminder> list) =>
        list.map((r) => r.kind).toSet();

    test('nothing to remind', () {
      expect(computeReminders(const ReminderFacts(), all, midMonth), isEmpty);
    });

    test('each rule fires on its facts', () {
      final facts = ReminderFacts(
        overdueBills: 2,
        overduePaise: 500000,
        activeWorkers: 3,
        holidayTomorrow: 'Diwali',
        backupConfigured: true,
        dirtySince: midMonth.subtract(const Duration(hours: 30)),
        clockSkewSeconds: 3600,
      );
      expect(kinds(computeReminders(facts, all, midMonth)), {
        NotificationKind.overdueBills,
        NotificationKind.holiday,
        NotificationKind.backupPending,
        NotificationKind.clockWrong,
      });
      final lastDay = DateTime(2026, 10, 31, 10);
      expect(kinds(computeReminders(facts, all, lastDay)),
          contains(NotificationKind.monthEnd));
    });

    test('switched-off reminders do not fire', () {
      final facts = ReminderFacts(
        overdueBills: 1,
        overduePaise: 100,
        holidayTomorrow: 'Holi',
        backupConfigured: true,
        dirtySince: midMonth.subtract(const Duration(days: 2)),
      );
      const none = ReminderSettings(
        backup: false,
        overdueBills: false,
        monthEnd: false,
        holidays: false,
      );
      expect(computeReminders(facts, none, midMonth), isEmpty);
    });

    test('pending under 24 hours is not a reminder', () {
      final facts = ReminderFacts(
        backupConfigured: true,
        dirtySince: midMonth.subtract(const Duration(hours: 5)),
      );
      expect(computeReminders(facts, all, midMonth), isEmpty);
    });

    test('quiet hours', () {
      expect(isReminderHour(DateTime(2026, 10, 3, 8, 59)), isFalse);
      expect(isReminderHour(DateTime(2026, 10, 3, 9)), isTrue);
      expect(isReminderHour(DateTime(2026, 10, 3, 21)), isFalse);
    });

    test('reminder settings survive the settings JSON', () {
      final settings = const AppSettings().copyWith(
        reminders: const ReminderSettings(monthEnd: false),
      );
      final back = AppSettings.fromJsonString(settings.toJsonString());
      expect(back.reminders.monthEnd, isFalse);
      expect(back.reminders.overdueBills, isTrue);
      expect(AppSettings.fromJsonString('{}').reminders.backup, isTrue);
    });
  });

  group('reminder facts from the database', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('counts overdue unpaid bills and active workers', () async {
      final billing = BillingRepository(db);
      final client = await billing.saveClient(name: 'Sharma');

      Future<String> bill(DateTime due, int ratePaise) async {
        final id = await billing.saveDocument(DocumentDraft(
          kind: DocumentKind.invoice,
          clientId: client,
          date: DateTime(2026, 9, 1),
          dueDate: due,
          lines: [
            DraftLine(
              lineType: LineType.lumpSum,
              name: 'Work',
              qtyMilli: 1000,
              ratePaise: ratePaise,
            ),
          ],
        ));
        await billing.markSentIfDraft(id);
        return id;
      }

      final overdue = await bill(DateTime(2026, 9, 30), 1000000);
      await bill(DateTime(2026, 10, 20), 500000); // not due yet
      final paidOff = await bill(DateTime(2026, 9, 15), 300000);
      await billing.recordPayment(
        clientId: client,
        documentId: overdue,
        amountPaise: 400000,
        mode: PaymentMode.cash,
        date: DateTime(2026, 10, 1),
      );
      await billing.recordPayment(
        clientId: client,
        documentId: paidOff,
        amountPaise: 300000,
        mode: PaymentMode.cash,
        date: DateTime(2026, 10, 1),
      );

      await WorkersRepository(db).addWorker(NewWorker(
        name: 'Raju',
        joinDate: DateTime(2026, 1, 1),
        wageModel: WageModel.daily,
        ratePaise: 60000,
      ));

      final facts =
          await ReminderService(db).readFacts(DateTime(2026, 10, 3, 10));
      expect(facts.overdueBills, 1);
      expect(facts.overduePaise, 600000);
      expect(facts.activeWorkers, 1);
      expect(facts.holidayTomorrow, isNull);
      expect(facts.backupConfigured, isFalse);
    });
  });
}
