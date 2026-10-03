# Thekedaar App: PRD, Design System aur Gap Analysis

> **Version:** 2.2 (har tarah ke contractor ke liye, mobile-only, offline, admin-only, auto backup on internet)  ·  **Date:** 2026-10-03
> **Platform:** Android app (Flutter). iOS baad mein, dekhein [I-M3](#b1-mobile-only-architecture-ke-risks)
> **User:** Sirf **Admin (thekedaar)**. Workers app use nahi karte, unka saara record admin rakhta hai.
> **Trades:** ✅ **Har type ka contractor**: Electrical, Plumbing, Civil / Construction, Painting, Tiles / Flooring, Carpentry / Interior, POP / False Ceiling, Fabrication / Welding, Labour Supply, ya Other. Setup ke waqt trade chuno, aur app usi hisaab se roles, units, items aur templates bhar deta hai ([C0](#c0-business-type-aur-trade-setup))
> **Server:** ❌ Koi server nahi. Saara data admin ke phone ki **SQLite** file mein rehta hai.
> **Backup:** ✅ Ek baar Google Drive permission lene ke baad **din mein 4 baar automatic** encrypted backup, aur naye phone par restore.
> **UI Language:** English only (simple words, bade icons)

### Version history
| Ver | Change |
|---|---|
| 1.0 | Original PRD (Next.js PWA, worker app, WebAuthn) |
| 1.1 | Issues aur gap analysis |
| 1.2 | SQLite + Google Drive backup, naye features, Hindi UI hataya |
| 1.3 | Server-based SQLite |
| **2.2** | ✅ **Generic contractor app**: sirf electrician nahi, har trade ke liye. Trade setup (C0), custom roles/units, "Points" ki jagah generic **Work-rate** line, measurement (L × W × H) billing, piece-rate (theka) worker payment, configurable expense categories |
| 2.1 | ✅ Offline → online auto backup: internet na ho to backup pending, aur internet aate hi apne aap (D3.1) |
| 2.0 | ✅ **Final direction: server nahi, app sirf admin ke mobile par chalega. Google Drive par din mein 3–4 baar auto backup.** Worker app, WebAuthn, geofence aur multi-tenant hataye. Stack Next.js PWA se Flutter kiya (wajah: [I-M1](#b1-mobile-only-architecture-ke-risks)) |

### Is document mein
1. **Part A**: architecture (mobile-only) aur tech stack
2. **Part B**: issues, risks aur unke fixes
3. **Part C**: functional requirements (module-wise)
4. **Part D**: Google Drive backup aur restore ki spec
5. **Part E**: screens aur design system
6. **Part F**: data model (SQLite)
7. **Part G**: roadmap (phases)
8. **Part H**: v1 ke kaunse features hataye gaye aur kyu
9. **Part I**: open decisions
10. **Part J**: default seed data (sabhi trades)

---

## Part A: Architecture aur Tech Stack

### A1. Data Flow
```
┌──────────────────────────────────────────┐
│  Admin ka Android Phone (Flutter app)    │
│                                          │
│  UI (screens)                            │
│     │                                    │
│  Business logic (Riverpod)               │
│     │                                    │
│  SQLite  app.db   ◄── source of truth    │
│  files/  (photos, logo)                  │
│                                          │
│  Backup engine (WorkManager)             │
│   - 4 baar roz (scheduled)               │
│   - app band karte waqt (agar changes)   │
│   - internet wapas aate hi (pending)     │
│   - "Backup Now" button                  │
└──────────────┬───────────────────────────┘
               │ HTTPS (Google Drive API, scope: drive.file)
               ▼
┌──────────────────────────────────────────┐
│  Admin ka apna Google Drive              │
│  Thekedaar Backups/                      │
│    device.json                           │
│    db/   2026-10-03_1400_v3.tkbak        │
│    files/ <hash>.enc                     │
└──────────────────────────────────────────┘
```
- Koi server ya API nahi, aur koi monthly kharcha nahi.
- App **poori tarah offline** chalta hai. Internet sirf backup aur restore ke liye chahiye.
- Google Drive sirf **backup store** hai, live database nahi.

### A2. Tech Stack
| Kaam | Package | Kyu |
|---|---|---|
| Framework | Flutter (stable), Dart 3 | Native Android app, aur aage iOS bhi isi code se |
| State management | `flutter_riverpod` | Industry standard, testable |
| Navigation | `go_router` | Declarative routes, app lock redirect |
| Database | `drift` (SQLite) | Type-safe queries, **versioned migrations**, reactive streams |
| Background backup | `workmanager` | Android WorkManager, jo app band hone par bhi chalta hai, aur network constraint se internet aane ka intezaar karta hai |
| Connectivity | `connectivity_plus` | App khula ho to internet aate hi turant pending backup |
| Google login + Drive | `google_sign_in` + `googleapis` (Drive v3) | Official Google packages |
| Encryption | `cryptography` (AES-256-GCM + Argon2id) | Backup encrypt karne ke liye |
| Zip | `archive` | DB + manifest ko ek file mein pack karna |
| App lock | `local_auth` + `flutter_secure_storage` | Fingerprint/Face, aur PIN hash secure storage mein |
| PDF | `pdf` + `printing` | Invoice, quotation, pay-slip |
| Share | `share_plus` | PDF **file seedha WhatsApp** par attach hoti hai |
| Photos | `image_picker` + `flutter_image_compress` | Site photos, bill photos (compressed) |
| Notifications | `flutter_local_notifications` | Backup fail, overdue bill, month-end reminder |
| Location (optional) | `geolocator` | Attendance lagate waqt site location tag |
| Formatting | `intl` | ₹1,25,000 Indian number format, dates |
| Models | `freezed` + `json_serializable` | Immutable models, manifest JSON |
| Code quality | `very_good_analysis`, `flutter_test`, `mocktail` | Lint aur tests |

### A3. Folder Structure
```
lib/
  main.dart
  app/                    # app widget, router, theme, app-lock gate
  core/
    db/                   # drift database, tables, migrations, DAOs
    backup/               # backup engine, drive client, crypto, scheduler
    pdf/                  # pdf builders (invoice, quotation, payslip)
    utils/                # money (paise), date (IST), phone formatter
    widgets/              # buttons, numpad, amount text, status chip, empty state
  features/
    dashboard/
    billing/              # clients, quotations, invoices, payments, items, templates
    workers/              # workers, wages, attendance
    khata/                # advances, loans, settlements, payslips
    expenses/             # business expenses, suppliers
    jobs/                 # jobs, site reports
    settings/             # business profile, rules, backup screen, app lock
      (har feature: data/ · domain/ · presentation/)
test/
```

---

## Part B: Issues, Risks aur Fixes

Severity: 🔴 Critical · 🟠 High · 🟡 Medium

### B1. Mobile-only Architecture ke Risks

| ID | Sev | Issue | Kyu problem hai | Fix |
|---|---|---|---|---|
| I-M1 | 🔴 | **PWA (web app) mein background auto-backup possible nahi** | Browser app band hone par code nahi chalata. Periodic Background Sync sirf Chrome mein hai, aur din mein kitni baar chalega ye browser decide karta hai. Browser apna storage khud bhi saaf kar sakta hai | **Native Flutter app** banayein. Android WorkManager app band hone par bhi scheduled backup chalata hai |
| I-M2 | 🔴 | **Chinese brand phones (Xiaomi, Oppo, Vivo, Realme) background kaam kill kar dete hain** | Battery saver ki wajah se scheduled backup miss ho sakta hai | (1) Setup ke waqt "Battery optimization off karein" ka guided step. (2) Har baar app khulne aur band hone par check: last backup 6 ghante se purana ho aur changes hon to turant backup. (3) 24 ghante tak backup na ho to app khulte hi red banner |
| I-M3 | 🟠 | **iOS par background backup guaranteed nahi** | iOS khud decide karta hai ki background task kab chalega | Pehle **Android-only** launch karein. iOS version mein backup app band karte waqt aur khulte waqt chalega |
| I-M4 | 🔴 | **Do backups ke beech phone gaya to beech ka data jaayega** | 4 baar roz backup = zyada se zyada ~6 ghante ka data risk | **Change-based backup**: data badalne par dirty flag lagta hai, aur app background mein jaate hi 2 minute ke andar backup. **Internet na ho to backup pending rahega aur internet aate hi apne aap chalega** ([D3.1](#d31-offline--online-auto-backup-hamesha)). Saath mein 4 scheduled slots. Loss sirf tab hoga jab entry ke baad internet aane se pehle hi phone kho jaaye |
| I-M5 | 🔴 | **Ek waqt mein sirf ek phone par app** | Do phones par alag-alag entries hongi to merge nahi ho sakti. Purana phone aage chal kar naye phone ka backup overwrite kar sakta hai | Drive par `device.json` mein `activeDeviceId` save ho. Restore karne par naya phone "active" ban jaata hai. Purana phone agar kabhi dobara chale to backup se pehle check kare, aur active na ho to backup band karke warning dikhaye: "Ye data dusre phone par shift ho chuka hai" |
| I-M6 | 🔴 | **Live SQLite file ko seedha copy karna backup corrupt kar sakta hai** | Copy ke beech write aa jaaye to file adhoori banegi | `VACUUM INTO` se snapshot, phir `PRAGMA integrity_check`, aur tab hi upload |
| I-M7 | 🟠 | **Backup mein sensitive data hai** (phone numbers, paisa, locations) | Google account hack hone par data leak ho sakta hai | Upload se pehle AES-256-GCM encryption. Key **Backup Password** se banegi. Saath mein ek **Recovery Key** jo admin likh kar rakhe |
| I-M8 | 🟠 | **Backup Password aur Recovery Key dono bhool gaye** | Encrypted backup kabhi nahi khulega | Setup ke waqt saaf warning, aur Recovery Key ka screenshot ya likhne ka step. Encryption ka option ON by default rahega. Admin chahe to OFF kar sake, lekin "Not recommended" label ke saath |
| I-M9 | 🟠 | **Google permission revoke ho jaaye ya token expire** | Backups chupchaap band ho jaayenge | Har failed backup ka log rahe. "Google Drive disconnected" ka banner, aur 1-tap **Reconnect** |
| I-M10 | 🟠 | **Photos se backup bada aur slow hoga** | Har baar 200 MB upload karna practical nahi | DB backup chhota hota hai (KBs–MBs) aur har baar jaata hai. Photos **incremental** jaati hain: sirf nayi photo ek baar upload hoti hai (hash naam se). Photos 1280px aur ~200 KB tak compress hongi. Mobile data par sirf DB backup ka option |
| I-M11 | 🟡 | **Google Drive storage (15 GB free) bhar sakti hai** | Upload fail honge | Retention policy lagayein, Drive ka bacha space dikhayein, aur 90% bharne par warning |
| I-M12 | 🟡 | **Phone ka time galat ho** | Entries ki date/time galat hogi | Har entry par device time hi save hoga (single user hai to theek hai). Backup ke waqt Drive server ka time compare karein, aur 10 min se zyada farak ho to warning |
| I-M13 | 🟡 | **Phone storage full** | SQLite write fail ho sakta hai, data loss ka risk | 200 MB se kam free space par warning. Write errors pakad kar saaf message dikhayein, crash nahi |

### B2. Attendance Issues (admin marking ke hisaab se)
| ID | Sev | Issue | Fix |
|---|---|---|---|
| I-T1 | 🔴 | **Full / Half day / OT ke rules define nahi hain** | Settings: Full Day, Half Day, Absent ke saath OT hours (decimal mein, jaise 2.5) aur OT rate (₹/hour). Admin seedha status tap karega, hours ka calculation nahi |
| I-T2 | 🟠 | **20–30 workers ka roz attendance lagana slow ho sakta hai** | "Daily Attendance" screen: ek list, har worker ke aage P / ½ / A ke bade buttons. **"Mark All Present"** + exceptions. Kal ka attendance copy karne ka option |
| I-T3 | 🟠 | **Pichli date ka attendance badalna** | Allowed hai, lekin har change audit log mein jaayega. Settled (locked) month ka attendance edit nahi hoga |
| I-T4 | 🟡 | **Sunday, holiday aur leave** | Holiday calendar, weekly off setting, aur leave types (paid / unpaid) |
| I-T5 | 🟡 | **Worker kis site par tha** | Attendance ke saath optional site/job select karein. Isse job ka labour cost nikalega |

### B3. Salary aur Khata Issues
| ID | Sev | Issue | Fix |
|---|---|---|---|
| I-S1 | 🔴 | **Monthly wage par "Working Days × Rate" galat hai** | Setting: `perDay = monthly / (30 \| 26 \| daysInMonth)`. Paid days = Present + 0.5 × Half + paid leaves + paid weekly offs |
| I-S2 | 🔴 | **Settlement mein "balance zero" karne se data loss hoga** | Settlement = period lock + paid amount + bacha balance **carry-forward**. Advance > earning ho to minus balance aage jaayega |
| I-S3 | 🟠 | **Half Day aur OT formula mein nahi hain** | `Earning = (Full + 0.5×Half + paidLeave) × dayRate + OTHours × otRate + Σ(pieceQty × pieceRate) + bonus − deductions − EMI` |
| I-S4 | 🟠 | **Advance entry edit/delete se hisaab bigad sakta hai** | Entries immutable hon. Galti ho to **reversal entry** bane. Har change audit log mein |
| I-S5 | 🟠 | **Mahine ke beech mein wage rate badalna** | `WageHistory (effectiveFrom)`. Calculation date-wise rate se |
| I-S6 | 🟡 | **Floating point paisa** | Amount **paise mein INTEGER** (₹600 = 60000). Decimal qty milli-units mein (12.5 m = 12500) |

### B4. Billing Issues
| ID | Sev | Issue | Fix |
|---|---|---|---|
| I-B1 | 🟠 | **Non-GST bill ka compliance risk** (contractor GST registered ho to, CA se confirm karein) | PDF par "Estimate, not a tax invoice" label |
| I-B2 | 🔴 | **Client aur client payments missing** ("pending client balance" kahan se aayega?) | `Client` + `PaymentReceived` (partial payments) + client ledger |
| I-B3 | 🟠 | **"Active Job" define nahi** | Job = client + site address + status (Planned / In-Progress / Completed) + linked quotation, invoices, expenses |
| I-B4 | 🟠 | **Invoice numbering, discount, round-off** | Har financial year ka sequence (`INV/26-27/0001`), transaction mein. Discount (₹/%) aur round-off line |
| I-B5 | 🟢 | **`wa.me` se PDF attach nahi hota** | ✅ Native app mein solve: `share_plus` se PDF **file** seedha WhatsApp chat mein jaati hai. Saath mein `wa.me` text option bhi |
| I-B6 | 🟡 | **Bheje hue bill ko edit karna** | Status: Draft → Sent → Partially Paid → Paid / Cancelled. Sent ke baad edit karne par naya revision |
| I-B7 | 🟡 | **Phone number format** | Save karte waqt +91 mein normalize. Phone contacts se pick karne ka option |

### B5. Design System Issues
| ID | Sev | Issue | Fix |
|---|---|---|---|
| I-D1 | 🔴 | **White par contrast fail** (WCAG AA: 4.5:1): `#f59e0b` 2.15 · `#d97706` 3.19 · `#059669` 3.77 · `#0284c7` 4.10 | Text/icon ke liye: amber `#b45309` (5.02) · green `#047857` (5.48) · blue `#0369a1` (5.93) · rose `#be123c` (6.29). Bright shades sirf fill ke liye, aur unpar text `#0f172a` |
| I-D2 | 🟠 | **Amber button par white text** (2.15:1) | Amber par dark text `#0f172a` (8.31:1) |
| I-D3 | 🟡 | **Sirf color se status** | Icon + label bhi (✓ Present, ½ Half, ✕ Absent) |
| I-D4 | 🟡 | **Lambe English labels** | Chhote shabd ("Advance", "Khata", "Bill"), bade icons, bade numbers |

---

## Part C: Functional Requirements

### C0. Business Type aur Trade Setup
App kisi ek trade ke liye hardcoded nahi hai. Saari trade-specific cheezein (roles, units, items, templates, expense categories) **data** hain, code nahi. Trade sirf shuruaati defaults bharta hai, baad mein sab badal sakte hain.

| ID | Requirement |
|---|---|
| TR-01 | Onboarding par **"What work do you do?"**: ek ya zyada trades chuno (multi-select, kyunki bahut contractor civil + plumbing jaise kaam saath karte hain) |
| TR-02 | Trades: Electrical · Plumbing · Civil / Construction · Painting · Tiles / Flooring · Carpentry / Interior · POP / False Ceiling · Fabrication / Welding · Labour Supply · Other |
| TR-03 | Chune gaye trades ke hisaab se **default seed data**: worker roles, units, item master (rate list), quotation templates, expense categories (neeche table) |
| TR-04 | Sab kuch editable: admin apna role, unit, item, template, category add / rename / hide kar sake |
| TR-05 | Baad mein Settings → Business → Trades se naya trade jodna. Jodne par sirf us trade ke defaults add hon, purana data na badle |
| TR-06 | Koi bhi screen, label ya PDF kisi ek trade ka shabd hardcode na kare (jaise "Wiring", "Point"). Ye sab master data se aaye |

**Default seed (short overview, poori list [Part J](#part-j-default-seed-data-sabhi-trades) mein):**
| Trade | Worker roles | Common units | Example items / work-rate | Example template |
|---|---|---|---|---|
| Electrical | Helper, Electrician, Wireman | point, meter, nos | Light point, Fan point, 6A socket, MCB, wire (meter) | 2BHK Full Wiring |
| Plumbing | Helper, Plumber | point, running ft, nos | CPVC line (rft), WC fitting, Tap point | Bathroom Plumbing |
| Civil / Construction | Labour (Beldar), Mistri (Mason), Shuttering, Bar bender | sq.ft, cu.ft, cu.m, brass, bag, ton | Brickwork (cu.ft), Plaster (sq.ft), RCC (cu.m), Cement (bag), Sand (brass) | Slab Work, Boundary Wall |
| Painting | Helper, Painter | sq.ft, litre | Putty 2 coat (sq.ft), Emulsion (sq.ft), Texture | 2BHK Interior Paint |
| Tiles / Flooring | Helper, Tile Mistri | sq.ft, box | Floor tiling (sq.ft), Wall dado (sq.ft), Skirting (rft) | Kitchen + Bathroom Tiles |
| Carpentry / Interior | Helper, Carpenter | sq.ft, running ft, nos | Wardrobe (sq.ft), Modular kitchen (rft), Door fitting | Bedroom Wardrobe |
| POP / False Ceiling | Helper, POP Mistri | sq.ft, running ft | Gypsum ceiling (sq.ft), Cove (rft) | Hall False Ceiling |
| Fabrication / Welding | Helper, Welder, Fitter | kg, running ft, sq.ft | MS grill (kg), Gate (sq.ft), Shed (sq.ft) | Main Gate |
| Labour Supply | Labour, Mistri, Supervisor | day, hour | Labour per day, OT per hour | Monthly Labour Bill |

### C1. App Lock aur Security (server login ki jagah)
| ID | Requirement |
|---|---|
| AU-01 | App kholne par **fingerprint / face** (`local_auth`) |
| AU-02 | Fallback **4-digit PIN** (bada numpad). Hash secure storage mein. 1234, 0000 jaise PIN allowed nahi |
| AU-03 | 5 galat PIN par 30 sec ka wait, aur har agle galat try par wait double |
| AU-04 | App background mein 2 min se zyada rahe to dobara lock |
| AU-05 | PIN bhool gaye to **Google account se verify** karke naya PIN set karein. Usi Google account se jo backup ke liye connect hai |
| AU-06 | Restore, backup settings badalna aur data delete karne se pehle dobara biometric/PIN |
| AU-07 | Screenshot block (`FLAG_SECURE`) amount wali screens par (setting se ON/OFF) |

### C2. Workers aur Wage Setup
| ID | Requirement |
|---|---|
| WK-01 | Worker add karein: naam, phone, photo (optional), role (trade ke default roles se, ya apna naya role), joining date, UPI ID (optional) |
| WK-02 | Wage model: **Daily** (₹600/din), **Monthly** (₹18,000/mahina), ya **Piece-rate / Theka** (₹/unit, jaise tile mistri ₹25/sq.ft, painter ₹12/sq.ft) + OT rate (₹/hour). Ek worker ka daily wage aur piece-rate dono ho sakte hain |
| WK-05 | **Piece-work entry**: worker, date, job, kaam (item master se), qty + unit, rate → amount. Settlement ki earning mein judega (I-S3) |
| WK-03 | Wage rate history (`effectiveFrom`) |
| WK-04 | Worker Active / Inactive (chhod gaya). Inactive ka record rahega, aur pending balance dikhega |

### C3. Attendance (admin marks)
| ID | Requirement |
|---|---|
| AT-01 | **Daily Attendance screen**: date picker (default aaj), saare active workers, har ek ke aage **P / ½ / A** buttons (min 48px), OT hours stepper |
| AT-02 | **Mark All Present** + exceptions. "Copy yesterday" ka option |
| AT-03 | Optional: site/job select, aur admin ki current GPS location tag (proof ke liye) |
| AT-04 | **Monthly calendar view** per worker (color + icon grid) |
| AT-05 | Holidays, weekly off, leave (paid/unpaid) |
| AT-06 | Locked (settled) period edit nahi hoga |

### C4. Khata: Advance, Loan aur Settlement
| ID | Requirement |
|---|---|
| KH-01 | **Advance entry**: worker, amount, date+time, mode (Cash / Paytm / PhonePe / GPay / Bank), remarks. Bada numpad, 2 tap mein entry |
| KH-02 | Entries immutable. Galti ho to **Reverse** button se reversal entry bane |
| KH-03 | **Worker summary card**: is mahine ke din, kul kamai, advance liya, bacha hisaab (live) |
| KH-04 | **Loan + EMI**: bada udhaar alag, har settlement mein EMI khud kate |
| KH-05 | **Advance limit warning**: kamai se zyada advance par warning (block nahi) |
| KH-06 | **Month-end settlement**: Earning (I-S3 formula) − Advance − EMI = Net Payable. "Paid amount" daalein, bacha carry-forward ho, aur period lock ho |
| KH-07 | **Bulk settlement**: saare workers ki list, checkbox, ek saath settle |
| KH-08 | **Pay via UPI**: `upi://pay?pa=<id>&pn=<name>&am=<amt>&tn=Salary Oct`. Wapas aane par "Paid?" confirm, aur PAYMENT entry |
| KH-09 | **Pay-slip PDF** share karein (WhatsApp par file) |
| KH-10 | Settlement reverse ho sake (admin re-verify + audit log) |

### C5. Billing aur Quotation (Non-Tax)
| ID | Requirement |
|---|---|
| BL-01 | **Clients**: naam, phone (contacts se pick), address. Client ledger (billed, received, outstanding) |
| BL-02 | **Quotation aur Invoice**, bina GST/tax field ke. Label "Estimate / Bill (Non-Tax)" |
| BL-03 | Line types: **Material** (item, qty, unit, rate) · **Labour** (days / hours × rate) · **Work-rate** (kaam × unit rate, jaise ₹350/point, ₹18/sq.ft plaster, ₹45/rft pipe, ₹90/kg grill) · **Lump-sum** · ek bill mein mixed bhi |
| BL-04 | Units master: nos, point, meter, running ft, sq.ft, sq.m, cu.ft, cu.m, brass, kg, ton, bag, box, litre, day, hour, trip, lot. Admin apni unit add kar sake. Decimal qty |
| BL-16 | **Measurement (naap) se qty**: line par L × W (× H) ya L × H daalo, nos se multiply, aur deductions (jaise darwaza/khidki ka area minus). Qty khud bane, aur PDF par naap ka breakup optional dikhe. Painting, tiles, plaster, POP, civil ke liye zaroori |
| BL-17 | Units ke beech simple conversion (sq.ft ↔ sq.m, cu.ft ↔ cu.m, cu.ft ↔ brass) |
| BL-05 | Discount (₹/%), round-off, notes, Terms & Conditions |
| BL-06 | **Item master / rate list**: search karke add, rate auto-fill |
| BL-07 | **Templates**: trade ke hisaab se ready lines aur terms (jaise "2BHK Full Wiring", "Bathroom Plumbing", "2BHK Interior Paint", "Slab Work"). Admin apna template kisi bhi bill se "Save as template" kar sake |
| BL-08 | **Instant Convert**: Quotation → Job → Invoice (1 tap). Quotation snapshot read-only |
| BL-09 | **Running Bill (RA)**: contract value ka % stage-wise billing, pichla billed aur ab ka due |
| BL-10 | Numbering: `QT/26-27/0001`, `INV/26-27/0001` (financial year reset) |
| BL-11 | **PDF**: business logo, naam, phone, **UPI QR** (invoice amount ke saath), signature image |
| BL-12 | **Share**: PDF file WhatsApp/any app par (`share_plus`) + pre-filled WhatsApp text (`wa.me`) |
| BL-13 | **Payment received** (partial bhi): amount, mode, date. Invoice status khud update |
| BL-14 | **Payment reminder**: overdue bill par pre-filled WhatsApp message |
| BL-15 | **Duplicate** bill/quotation, aur status flow (Draft → Sent → Partially Paid → Paid / Cancelled) |

### C6. Jobs, Expenses aur Suppliers
| ID | Requirement |
|---|---|
| JB-01 | Job: client, title, site address, status, linked quotation/invoices |
| JB-02 | **Daily site report**: notes + photos (before / after / progress), PDF/photos share |
| EX-01 | **Business expense**: category (default: Material, Petrol, Food, Transport, Tools, Machine Rent, Other; trade ke hisaab se extra jaise Shuttering Rent, Scaffolding; admin apni category bana sake), amount, mode, job (optional), bill photo |
| EX-02 | **Supplier khata**: udhaar purchase aur payment, due balance |
| EX-03 | **Job profit**: invoice total − material − labour (attendance × day rate + piece-work) − other expense |

### C7. Dashboard, Reports aur Utility
| ID | Requirement |
|---|---|
| DB-01 | Header: business name, **pending client balance** pill, backup status dot (green/amber/red) |
| DB-02 | Quick actions: **[+ New Bill]**, **[+ Advance]**, **[Today's Attendance]** |
| DB-03 | Today strip: aaj present workers ke avatars (green badge) |
| DB-04 | KPI cards: is mahine ki billing, collection, outstanding, labour cost, expense. 6 mahine ka trend |
| DB-05 | **Reports (PDF / Excel)**: salary sheet, attendance register, client outstanding, job profit, expense report |
| DB-06 | **Global search**: client, worker, bill number, phone |
| DB-07 | **Local notifications**: backup failed, overdue bill, month-end settlement reminder, holiday |
| DB-08 | Themes: Light, Dark, **Sunlight** (high contrast, bade fonts) |
| DB-09 | Audit log viewer (kisne kya kab badla, before/after) |

---

## Part D: Google Drive Backup aur Restore

### D1. One-time Setup (Onboarding ke time)
| Step | Kya hoga |
|---|---|
| 1 | Pehli baar app kholne par: **"Protect your data: Connect Google Drive"** |
| 2 | Google Sign-In → permission screen. Scope sirf `drive.file`, yaani app sirf apni banayi files dekh sakti hai, aapki baaki Drive nahi |
| 3 | Drive mein folder bane: `Thekedaar Backups/` |
| 4 | **Backup Password** set karein (min 8 characters). App ek **Recovery Key** (24 characters) dikhaye, jo likh kar rakhni hai. App confirm karwaye ki key likh li gayi |
| 5 | Backup time slots choose karein (default 4 slots, Part D3) aur network: **Wi-Fi + Mobile data** (default) ya sirf Wi-Fi |
| 6 | **Battery optimization off** karne ka guided step (I-M2) |
| 7 | Pehla backup turant, aur success screen ✓ |
| — | Skip bhi kar sakte hain, lekin dashboard par lagataar "Backup not set up" ka red banner rahega |

### D2. Drive Folder Structure
```
Thekedaar Backups/
  device.json                          # { activeDeviceId, deviceName, lastBackupAt, schemaVersion }
  db/
    2026-10-03_1400_v3.tkbak           # encrypted DB snapshot (har backup)
    2026-10-03_1000_v3.tkbak
    ...
  files/
    3f9a…c2.enc                        # har photo/logo ek baar, encrypted, hash naam se
    files-index.tkbak                  # kaunsi file kis record ki hai
```

### D3. Backup Kab Chalega (3 triggers)
| Trigger | Kab | Note |
|---|---|---|
| **Scheduled** | Roz 4 slots: **10:00, 14:00, 18:00, 22:00** (Settings mein 3 ya 4 slots, time badal sakte hain) | WorkManager, network ke saath. Sirf tab chale jab pichle backup ke baad changes hue hon |
| **On change** | Data badla aur app background mein gaya, to ~2 min baad | Phone gaya to data loss kam se kam (I-M4) |
| **Manual** | "Backup Now" button | Turant chalega, progress dikhegi |
| **Internet wapas aate hi** ✅ | Backup due tha (scheduled/on-change/manual) lekin internet nahi tha | Backup **pending** mark hota hai, aur internet (Wi-Fi ya mobile data) aate hi **apne aap** chal jaata hai, chahe app band ho (D3.1) |
| **Safety net** | App khulte waqt: last success 24 ghante se purana ho | Turant backup try, aur fail ho to red banner |

#### D3.1 Offline → Online Auto Backup (hamesha)
Goal: bina internet ke jo bhi entry hui, wo internet aate hi Drive par pahunch jaaye. Admin ko kuch karna na pade.

```
Data badla (koi bhi entry / edit)
   │
   ├─► AppMeta.dirtySince = now         (pending changes ka flag)
   ├─► Local snapshot turant: app storage mein encrypted .tkbak
   │     (aakhri 3 local copies; DB corruption se bachav, aur
   │      internet aate hi isi ko upload kiya ja sakta hai)
   └─► WorkManager one-time "backup-pending" job enqueue
         constraint: NetworkType.CONNECTED (Wi-Fi-only setting ho to UNMETERED)
         policy: KEEP (ek hi pending job, duplicate nahi)
         backoff: exponential, 1 min se 1 ghanta tak
             │
     Internet nahi ─► Android job ko hold rakhta hai (app band ho tab bhi)
             │
     Internet aaya ─► Android job chalata hai ─► D4 backup engine
             │
     Success ─► dirtySince clear, pending job khatam ✓
     Fail    ─► retry (backoff), dirtySince bana rahega
```
- **Teen safety layers:**
  1. **WorkManager network constraint**: OS khud internet ka intezaar karta hai, app band ho tab bhi.
  2. **App khulte waqt / foreground mein connectivity listener** (`connectivity_plus`): internet aate hi aur `dirtySince` set ho to turant backup. Ye un phones ke liye hai jo background job kill kar dete hain (I-M2).
  3. **Scheduled slots**: agar pending ho to slot par bhi try hoga.
- **Local snapshot ka fayda:** internet aane tak data phone mein ek alag encrypted copy mein bhi safe hai, aur upload ke waqt naya snapshot banane ki zaroorat nahi (agar beech mein aur changes nahi hue).
- **Status har jagah dikhe:** dashboard ka backup dot
  - 🟢 Synced: sab Drive par hai
  - 🟡 **Pending: "3 changes waiting for internet"**
  - 🔴 Failed / 24h+ se backup nahi
- Pending 24 ghante se zyada ho to local notification: "Backup pending — connect to internet".
- Photos bhi isi pending queue mein rehti hain aur internet aate hi upload hoti hain (Wi-Fi-only setting ho to Wi-Fi par).

### D4. Backup Engine Steps
```
1. Lock check: dusra backup chal raha ho to skip
2. device.json padho → activeDeviceId == ye phone? Nahi to STOP + warning (I-M5)
3. VACUUM INTO cache/snap.db                ← consistent copy, app chalta rahe
4. PRAGMA integrity_check (snap.db)         ← corrupt copy upload na ho
5. zip(snap.db + manifest.json) → AES-256-GCM encrypt → .tkbak
6. Drive par upload (resumable, 3 retries, exponential backoff)
7. Nayi photos: hash → Drive par nahi hai to encrypt + upload (incremental)
8. device.json update (lastBackupAt), BackupLog = SUCCESS
9. Retention cleanup (D5), temp files delete
Fail: BackupLog = FAILED (reason). 2 lagatar fail ho to local notification
```
`manifest.json`: `{ appVersion, schemaVersion, deviceId, createdAt, counts: {workers, clients, invoices, ledgerEntries, attendanceDays}, sha256 }`

Encryption: `Key = Argon2id(Backup Password, salt)`. Recovery Key se bhi wahi master key khulti hai (key-wrapping). Password badalne par purane backups bhi khulte rahenge.

### D5. Retention (kitne backup rakhne hain)
- Pichle **3 din ke saare** backups (~12)
- Uske pehle ke **30 din**: har din ka aakhri backup
- Uske pehle ke **12 mahine**: har mahine ka aakhri backup
- Baaki Drive se auto-delete. Photos (`files/`) tab tak rahengi jab tak koi record unhe use karta hai

### D6. Restore Flow (naya phone / phone reset)
```
1. Naye phone par app install → "Restore from Google Drive"
2. Google Sign-In (wahi account)
3. Backups ki list: date, time, size, aur counts ("24 workers · 96 invoices · 3 Oct, 2:00 PM")
   Default: sabse latest
4. Backup Password (ya Recovery Key)
5. Download → decrypt → sha256 + integrity_check
6. schemaVersion purana ho → migrations chalengi. Naya ho → "Please update the app"
7. Photos download (background mein, progress ke saath)
8. device.json → activeDeviceId = naya phone   ← purana phone ab backup nahi karega
9. Naya App Lock PIN set karein → Dashboard ✓
```
- **Restore on same phone** (galti sudharne ke liye): Settings → Backup → Restore → koi purana backup. Restore se pehle current data ka **PRE_RESTORE** backup Drive par banega, taaki undo ho sake.
- **Download Backup File**: `.tkbak` ko phone storage ya PC mein save karna (extra copy). **Import from File** se ye file restore ho sakti hai.
- Restore atomic hoga: pehle temp file mein, phir swap. Beech mein app band ho to bhi purana data safe rahega.

### D7. Backup Screen
```
+---------------------------------------+
| Google Drive    ● Connected           |
| ramesh.contractor@gmail.com           |
+---------------------------------------+
| Last backup   Today 2:00 PM  ✓        |
| Status        ● Pending (no internet) |
|               3 changes will upload   |
|               when internet is back   |
| Next backup   Today 6:00 PM           |
| Size 3.8 MB  ·  Drive free 11.2 GB    |
+---------------------------------------+
| [   Backup Now   ]          56px      |
| [ Restore from Drive ]                |
| [ Download File ]  [ Import File ]    |
+---------------------------------------+
| Schedule   10:00 · 14:00 · 18:00 · 22:00  >
| Network    Wi-Fi + Mobile data        >
| Change Backup Password                >
+---------------------------------------+
| History                               |
| 03 Oct 2:00 PM   3.8 MB  ✓ Auto       |
| 03 Oct 11:42 AM  3.8 MB  ✓ On change  |
| 03 Oct 10:00 AM  3.7 MB  ✓ Auto       |
| 02 Oct 10:00 PM  —       ⏳ Waiting   |
| 02 Oct 10:41 PM  3.7 MB  ✓ Internet back |
+---------------------------------------+
```

### D8. Acceptance Criteria
- [ ] Backup ke dauraan app normal chale (entry save block na ho)
- [ ] 5 MB DB ka backup 4G par 30 sec ke andar ho jaaye
- [ ] App band ho tab bhi scheduled backup chale (stock Android + Xiaomi par test karein)
- [ ] Galat password par saaf error, crash nahi
- [ ] Corrupt ya adhoori file restore na ho
- [ ] Restore ke beech app band ho jaaye to bhi purana data safe rahe
- [ ] Purane schema version ka backup naye app version mein restore ho
- [ ] Restore ke baad purana phone backup overwrite na kare (I-M5)
- [ ] 24 ghante tak backup na hone par app mein red banner dikhe
- [ ] Airplane mode mein 5 entries → app band → internet on: **app khole bina** 15 min ke andar backup Drive par ho (stock Android)
- [ ] Wahi test Xiaomi/Oppo par: app kholte hi turant backup ho (connectivity listener)
- [ ] Offline mein dashboard dot 🟡 "Pending" dikhaye, aur upload ke baad 🟢
- [ ] Internet baar-baar aaye-jaaye to bhi duplicate ya adhoore backups na banein

---

## Part E: Screens aur Design System

### E1. Navigation
```
App Lock (biometric / PIN)
└── Bottom tabs
    ├── Dashboard   → quick actions, today strip, KPIs, backup status
    ├── Billing     → Invoices | Quotations | Clients | Payments
    ├── Khata       → Advances | Loans | Settlements
    └── Workers     → list → Worker detail (summary card, calendar, entries)
Header menu → Attendance · Jobs · Expenses · Suppliers · Reports · Settings (Business, Rules, Items, Templates, Backup, App Lock, Theme)
```

### E2. Key Screens
**Dashboard:** header (business name, outstanding pill, backup dot) → 3 quick-action cards (**+ New Bill**, **+ Advance**, **Today's Attendance**) → today present strip → KPI cards → recent activity.

**Worker Detail (pehle wala "Mera Khata" card ab yahan hai):**
```
+-----------------------------------+
| (photo) Raju · Helper · ₹600/day  |
+-----------------------------------+
| This month      21 days           |
| Earned          ₹12,600           |
| Advance taken   ₹4,000   (amber)  |
| Balance         ₹8,600   (green)  |
| [ + Advance ]  [ Settle ]         |
+-----------------------------------+
| Calendar (P/½/A grid)             |
| Recent entries (last 5)           |
+-----------------------------------+
```

**Advance Entry:** worker select → bada numpad (28px) → mode chips (Cash / PhonePe / Paytm / GPay / Bank) → note → **Save** (56px). 2–3 tap mein entry, aur haptic feedback ke saath ✓ animation.

### E3. Design Tokens (Flutter `ThemeData` mein map honge)
```
Brand
  slate900  #0f172a   dark bg, primary text
  amber500  #f59e0b   accent FILL only (text on it = slate900)
  blue600   #0284c7   fill / large text
  blue700   #0369a1   links & small text on white (5.93:1)
Surface
  surface   #ffffff   surface2 #f8fafc   border #e2e8f0
Semantic (fill / text-on-white)
  success   #059669 / #047857 (5.48:1)
  warning   #d97706 / #b45309 (5.02:1)
  danger    #e11d48 / #be123c (6.29:1)
Touch & type
  tapMin 48 · tapPrimary 56 · gap 8 · radius 12
  font: Inter (bundled) → system fallback
  input 20 · numpad 28 · amount 24 · body 16
```
UI rules:
- Do tappable cheezon ke beech kam se kam 8px gap.
- ₹ Indian format (`NumberFormat.currency(locale: 'en_IN', symbol: '₹')`).
- Har status par icon + label.
- Har list ke liye skeleton aur empty state (illustration + ek action button).
- Haptic feedback (`HapticFeedback.mediumImpact`) save aur attendance par.
- Portrait lock.

---

## Part F: Data Model (SQLite, drift)

Conventions:
- `id` = **UUID (TEXT)**. Aage kabhi server ya sync jodna ho to conflict nahi hoga.
- Har table mein `createdAt`, `updatedAt` (INTEGER epoch ms), aur zaroorat ho to `deletedAt` (soft delete).
- Paisa `INTEGER` paise mein. Qty `INTEGER` milli-units mein.
- `PRAGMA user_version` = schema version. drift migrations har version ke liye.
- PRAGMAs: `journal_mode=WAL`, `foreign_keys=ON`.

```
BusinessProfile(id, name, phone, address, logoPath, upiId, signaturePath, invoicePrefix, quotationPrefix, trades JSON[ELECTRICAL|PLUMBING|CIVIL|PAINTING|TILES|CARPENTRY|POP|FABRICATION|LABOUR_SUPPLY|OTHER], settings JSON)

# Master data (trade seed se bharta hai, admin edit kar sakta hai)
Role(id, name, trade?, sort, isHidden)
Unit(id, code, name, dimension[COUNT|LENGTH|AREA|VOLUME|WEIGHT|TIME|OTHER], toBase REAL?, isHidden)   # conversion factor, paisa nahi hai isliye REAL theek hai
ExpenseCategory(id, name, trade?, sort, isHidden)

Worker(id, name, phoneE164, photoPath, roleId, joinDate, upiId, isActive)
WageHistory(id, workerId, model[DAILY|MONTHLY|PIECE], ratePaise, otRatePaise, monthlyDivisor[30|26|0=daysInMonth], effectiveFrom)
PieceWork(id, workerId, date, jobId?, itemId?, description, qtyMilli, unitId, ratePaise, amountPaise, settlementId?)
Attendance(id, workerId, date, status[PRESENT|HALF|ABSENT|LEAVE_PAID|LEAVE_UNPAID|OFF], otMilliHours, jobId?, lat?, lng?, note)
Holiday(id, date, name)

LedgerEntry(id, workerId, type[ADVANCE|PAYMENT|BONUS|DEDUCTION|EMI|REVERSAL|CARRY_FORWARD], amountPaise, mode, at, remarks, refId)
Loan(id, workerId, principalPaise, emiPaise, startMonth, status[ACTIVE|CLOSED])
Settlement(id, workerId, periodFrom, periodTo, earningPaise, advancePaise, emiPaise, paidPaise, carryForwardPaise, status[LOCKED|REVERSED])

Client(id, name, phoneE164, address)
Job(id, clientId, title, siteAddress, status[PLANNED|IN_PROGRESS|COMPLETED], contractValuePaise?)
Document(id, kind[QUOTATION|INVOICE], number, clientId, jobId?, status, date, dueDate, subtotalPaise, discountPaise, roundOffPaise, totalPaise, notes, terms, sourceQuotationId?, raStagePercent?, revision)
DocumentLine(id, documentId, sort, lineType[MATERIAL|LABOUR|WORK_RATE|LUMPSUM], itemId?, name, qtyMilli, unitId, ratePaise, amountPaise, measurement JSON?)
                                       # measurement: [{label, nos, l, w, h, isDeduction}] → qtyMilli (BL-16)
PaymentReceived(id, clientId, documentId?, amountPaise, mode, date, remarks)
ItemMaster(id, name, unitId, defaultRatePaise, kind[MATERIAL|WORK_RATE|LABOUR], trade?, isHidden)
Template(id, kind, name, trade?, lines JSON, terms)

Expense(id, categoryId, amountPaise, mode, date, jobId?, supplierId?, photoPath, remarks)
Supplier(id, name, phoneE164)
SupplierLedger(id, supplierId, type[PURCHASE|PAYMENT], amountPaise, date, remarks)
SiteReport(id, jobId, date, notes)
SiteReportPhoto(id, siteReportId, path, tag[BEFORE|AFTER|PROGRESS], fileHash)

AuditLog(id, entity, entityId, action[CREATE|UPDATE|REVERSE|DELETE], before JSON, after JSON, at)
BackupLog(id, trigger[SCHEDULED|ON_CHANGE|MANUAL|PRE_RESTORE], status[SUCCESS|FAILED|SKIPPED], driveFileId, sizeBytes, sha256, schemaVersion, startedAt, finishedAt, error)
SyncedFile(fileHash, driveFileId, uploadedAt)        # incremental photo backup ke liye
AppMeta(key, value)                                   # dirtySince, deviceId, lastBackupAt
```
Backup ki secret cheezein (refresh token, PIN hash, encryption key) **DB mein nahi**, `flutter_secure_storage` (Android Keystore) mein rahengi.

---

## Part G: Roadmap

### Phase 1: MVP
- App lock (biometric + PIN)
- **Trade setup (C0)**: multi-select trades + default roles, units, items, expense categories ka seed
- Business profile, settings, attendance aur wage rules
- Workers + wage history + **daily attendance** + calendar
- **Piece-rate / theka worker payment** (WK-02, WK-05): piece-work entry, settlement earning mein jode
- Khata: advance, reversal, worker summary, month-end settlement, pay-slip PDF
- Billing: clients, quotation/invoice (material, labour, work-rate, lump-sum), **measurement (L × W × H) se qty**, PDF + share, payment received, quotation → invoice convert
- **Google Drive backup (4 baar roz + on-change + manual) aur restore**
- Dashboard (quick actions, today strip, outstanding)

### Phase 2
- Item master, templates, running bill (RA), UPI QR on invoice, payment reminder, duplicate
- Loan + EMI, bulk settlement, pay via UPI, advance limit
- Trade-wise templates, unit conversion
- Jobs, expenses, supplier khata, job profit
- Reports (PDF/Excel), global search, KPI charts, Sunlight/Dark theme, local notifications, audit log viewer

### Phase 3
- Site reports with photos, holiday/leave management
- iOS version
- Optional: **worker app + cloud sync** (Turso / server). Isliye abhi se UUID ids aur `updatedAt` rakhe gaye hain
- AMC / maintenance contracts, inventory, tools tracking

---

## Part H: v1 se Hataye Gaye Features (aur kyu)

| Feature (v1) | Status | Wajah / Replacement |
|---|---|---|
| Worker app (punch screen, mera khata) | ❌ Hataya | Server nahi hai, to worker ke phone se data admin ke phone tak nahi jaa sakta. **Admin attendance lagata hai** (C3) |
| WebAuthn biometric login + 4-digit PIN (workers) | 🔁 Badla | Ab ye admin ka **App Lock** hai (C1) |
| Hardware device binding, admin master reset | ❌ Hataya | Workers app use nahi karte. Ek-phone rule backup ke `activeDeviceId` se lagta hai (I-M5) |
| Geo-tagged punch, geofence, anti-proxy | 🔁 Badla | Attendance ke saath **optional** admin GPS tag (AT-03) |
| Live worker strip (punched in) | 🔁 Badla | "Today present" strip, admin ke attendance se |
| Worker advance request | ❌ Hataya | Worker app nahi hai |
| Next.js PWA, Server Actions, service worker | 🔁 Badla | **Flutter native app** (I-M1: background backup) |
| Quotation accept link, client portal | ❌ Hataya | Public link ke liye server chahiye. PDF WhatsApp par jaata hai |
| Multi-tenant SaaS, supervisor role | ❌ Hataya | Single admin, single phone |
| Haptic feedback | ✅ Rakha | Native app mein Android aur iOS dono par chalega |

---

## Part I: Open Decisions

| # | Decision | Status / Recommendation |
|---|---|---|
| D-0 | Data kahan rahega | ✅ **Final: sirf admin ka phone (SQLite)**, server nahi |
| D-1 | Backup | ✅ **Final: Google Drive, din mein 3–4 baar auto** (default 4 slots + on-change) + ✅ **bina internet ke changes internet aate hi hamesha auto-backup** (D3.1) |
| D-2 | Platform | Recommended: **Flutter, Android pehle**. Confirm karein |
| D-3 | Backup encryption | Recommended: ON (Backup Password + Recovery Key). Confirm karein |
| D-4 | Monthly wage divisor | Recommended default: 30 (settings mein badal sakte hain) |
| D-5 | Mobile data par backup | Recommended: DB backup mobile data par bhi, photos sirf Wi-Fi par |
| D-6 | App name aur package id | Batana hai (jaise `com.<company>.thekedaar`) |
| D-7 | Google Cloud project (OAuth client) | Aapke Google account mein banega. Release keystore ka SHA-1 chahiye hoga |
| D-8 | Kaun-kaun se trades ka default seed data (roles, items, rates, templates) launch par | ✅ **Final: sabhi 9 trades + "Other"**, poori list [Part J](#part-j-default-seed-data-sabhi-trades) mein. Items bina rate ke aayenge (rate har sheher mein alag hai). Pehli baar use karne par admin rate daalega, aur wo yaad rahega |
| D-9 | Piece-rate Phase 1 mein ya Phase 2 mein | ✅ **Final: Phase 1** |

---

## Part J: Default Seed Data (sabhi trades)

Rules:
- Ye data app ke andar `assets/seed/<trade>.json` mein bundled hoga, aur trade chunne par (TR-03, TR-05) DB mein insert hoga.
- **Items ka default rate khaali** rahega, kyunki rate har sheher aur client ke hisaab se alag hai. Admin pehli baar bill mein rate daalega, aur wo item master mein save ho jaayega.
- Do trades mein same naam ka role, unit ya category ho (jaise "Helper") to ek hi baar banega (duplicate nahi).
- Har cheez admin edit, rename ya hide kar sakta hai. Seed dobara chalne par admin ke badlaav overwrite nahi honge.
- `M` = Material item, `W` = Work-rate item (kaam), `L` = Labour item.

### J0. Common (har trade ke saath)
| Type | Seed |
|---|---|
| Roles | Helper, Mistri, Supervisor, Driver |
| Units | nos, meter, running ft (rft), sq.ft, sq.m, cu.ft, cu.m, kg, ton, bag, box, litre, day, hour, trip, lot, set, point, brass |
| Expense categories | Material, Petrol / Diesel, Food / Chai, Transport / Bhada, Tools, Machine Rent, Mobile Recharge, Other |
| Labour items | `L` Labour per day (day) · `L` Mistri per day (day) · `L` OT (hour) |
| Default terms | Advance 50% kaam shuru hone par · Material client ki taraf se (agar alag likha na ho) · Extra kaam ka alag bill · Quotation 15 din ke liye valid |

### J1. Electrical
| Type | Seed |
|---|---|
| Roles | Electrician, Wireman |
| Work-rate items | `W` Light point (point) · `W` Fan point (point) · `W` 6A socket point (point) · `W` 16A power point (point) · `W` AC point (point) · `W` Geyser point (point) · `W` DB fitting (nos) · `W` Conduit concealed (rft) · `W` Conduit surface (rft) · `W` Earthing (set) · `W` Light / fan fitting (nos) · `W` Inverter wiring (lot) |
| Material items | `M` Wire 1 sq.mm (meter) · `M` Wire 1.5 sq.mm (meter) · `M` Wire 2.5 sq.mm (meter) · `M` Wire 4 sq.mm (meter) · `M` PVC conduit 20mm (nos) · `M` Switch 6A (nos) · `M` Socket 6A (nos) · `M` Socket 16A (nos) · `M` Switch plate (nos) · `M` MCB SP (nos) · `M` MCB DP (nos) · `M` RCCB (nos) · `M` DB 8-way (nos) · `M` LED panel (nos) · `M` Ceiling fan (nos) |
| Templates | 1BHK Full Wiring · 2BHK Full Wiring · 3BHK Full Wiring · Shop Wiring · Rewiring (Old House) |
| Expense extra | Electrical Material |

### J2. Plumbing
| Type | Seed |
|---|---|
| Roles | Plumber |
| Work-rate items | `W` Water point (point) · `W` CPVC line concealed (rft) · `W` PVC drain line (rft) · `W` WC / commode fitting (nos) · `W` Wash basin fitting (nos) · `W` Kitchen sink fitting (nos) · `W` Geyser fitting (nos) · `W` Overhead tank fitting (nos) · `W` Motor / pump fitting (nos) · `W` Pressure testing (lot) |
| Material items | `M` CPVC pipe 1/2 inch (nos) · `M` CPVC pipe 3/4 inch (nos) · `M` CPVC pipe 1 inch (nos) · `M` PVC pipe 4 inch (nos) · `M` Elbow / Tee (nos) · `M` Ball valve (nos) · `M` Concealed valve (nos) · `M` Tap / Bib cock (nos) · `M` Angle cock (nos) · `M` Floor trap (nos) · `M` Solvent cement (nos) · `M` Teflon tape (nos) |
| Templates | Bathroom Plumbing · Kitchen Plumbing · 2BHK Full Plumbing · Tank + Motor Fitting |
| Expense extra | Plumbing Material |

### J3. Civil / Construction
| Type | Seed |
|---|---|
| Roles | Beldar (Labour), Mason, Shuttering Carpenter, Bar Bender, Machine Operator |
| Work-rate items | `W` Excavation (cu.ft) · `W` PCC (cu.ft) · `W` RCC work (cu.m) · `W` Brickwork 9 inch (cu.ft) · `W` Brickwork 4.5 inch (sq.ft) · `W` Block work (sq.ft) · `W` Internal plaster (sq.ft) · `W` External plaster (sq.ft) · `W` Shuttering (sq.ft) · `W` Steel binding (kg) · `W` Slab casting (sq.ft) · `W` Waterproofing (sq.ft) · `W` Construction labour rate, theka (sq.ft) |
| Material items | `M` Cement (bag) · `M` Sand (brass) · `M` Aggregate 20mm (brass) · `M` Bricks (nos) · `M` AAC block (nos) · `M` TMT steel (kg) · `M` Binding wire (kg) · `M` Ready-mix concrete (cu.m) · `M` Waterproofing chemical (litre) |
| Templates | Slab Work · Boundary Wall · Room Construction · Plaster Work · Labour-rate Construction (per sq.ft) |
| Expense extra | Shuttering Rent, Mixer / Vibrator Rent, Water Tanker, JCB / Tractor |

### J4. Painting
| Type | Seed |
|---|---|
| Roles | Painter |
| Work-rate items | `W` Wall putty 2 coat (sq.ft) · `W` Primer coat (sq.ft) · `W` Interior emulsion 2 coat (sq.ft) · `W` Exterior emulsion 2 coat (sq.ft) · `W` Texture paint (sq.ft) · `W` Enamel on doors / grill (sq.ft) · `W` Wood polish (sq.ft) · `W` Waterproof coating (sq.ft) · `W` Repainting, only paint (sq.ft) |
| Material items | `M` Wall putty (bag) · `M` Primer (litre) · `M` Interior emulsion (litre) · `M` Exterior emulsion (litre) · `M` Enamel (litre) · `M` Thinner (litre) · `M` Sandpaper (nos) · `M` Masking tape (nos) |
| Templates | 1BHK Interior Paint · 2BHK Interior Paint · Exterior Paint · Repainting |
| Expense extra | Scaffolding / Ladder Rent, Paint Material |

### J5. Tiles / Flooring
| Type | Seed |
|---|---|
| Roles | Tile Mistri |
| Work-rate items | `W` Floor tiling (sq.ft) · `W` Wall dado tiling (sq.ft) · `W` Large vitrified tile (sq.ft) · `W` Marble / granite laying (sq.ft) · `W` Skirting (rft) · `W` Kitchen platform granite (rft) · `W` Staircase step (nos) · `W` Epoxy grouting (sq.ft) · `W` Old tile removal (sq.ft) |
| Material items | `M` Floor tiles (box) · `M` Wall tiles (box) · `M` Tile adhesive (bag) · `M` Grout / epoxy (kg) · `M` Cement (bag) · `M` Sand (brass) · `M` Tile spacers (nos) |
| Templates | Kitchen + Bathroom Tiles · 2BHK Flooring · Bathroom Dado · Granite Kitchen Platform |
| Expense extra | Tile Cutter Rent, Tile Material |

### J6. Carpentry / Interior
| Type | Seed |
|---|---|
| Roles | Carpenter, Polish Mistri |
| Work-rate items | `W` Wardrobe (sq.ft) · `W` Modular kitchen base (rft) · `W` Modular kitchen wall unit (rft) · `W` TV unit (sq.ft) · `W` Bed with storage (nos) · `W` Door fitting (nos) · `W` Door frame (nos) · `W` Wall paneling (sq.ft) · `W` Laminate pasting (sq.ft) · `W` Hardware fitting (lot) |
| Material items | `M` Plywood 18mm (sq.ft) · `M` Plywood 12mm (sq.ft) · `M` Laminate (nos) · `M` Edge banding (meter) · `M` Hinges (nos) · `M` Drawer channel (set) · `M` Handles (nos) · `M` Adhesive / Fevicol (kg) · `M` Screws / nails (box) |
| Templates | Bedroom Wardrobe · Modular Kitchen · 2BHK Interior · Door Fitting |
| Expense extra | Plywood / Hardware |

### J7. POP / False Ceiling
| Type | Seed |
|---|---|
| Roles | POP Mistri |
| Work-rate items | `W` Gypsum false ceiling (sq.ft) · `W` POP false ceiling (sq.ft) · `W` PVC ceiling (sq.ft) · `W` Grid ceiling (sq.ft) · `W` Cove / border (rft) · `W` POP punning on wall (sq.ft) · `W` Light cut-out (nos) |
| Material items | `M` Gypsum board (nos) · `M` POP (bag) · `M` GI channel (nos) · `M` Ceiling angle (nos) · `M` Screws (box) · `M` Joint tape (nos) |
| Templates | Hall False Ceiling · Bedroom False Ceiling · Office Grid Ceiling |
| Expense extra | Scaffolding Rent |

### J8. Fabrication / Welding
| Type | Seed |
|---|---|
| Roles | Welder, Fitter, Grinder Operator |
| Work-rate items | `W` MS grill (kg) · `W` MS gate (sq.ft) · `W` Window grill (sq.ft) · `W` MS railing (rft) · `W` SS railing (rft) · `W` Tin / sheet shed (sq.ft) · `W` Staircase (lot) · `W` Fabrication labour, theka (kg) · `W` Site welding (day) |
| Material items | `M` MS pipe (kg) · `M` MS angle (kg) · `M` MS flat (kg) · `M` Square pipe (kg) · `M` Roofing sheet (sq.ft) · `M` Welding rod (box) · `M` Cutting wheel (nos) · `M` Red oxide primer (litre) |
| Templates | Main Gate · Window Grills · Terrace Shed · Railing |
| Expense extra | Welding Machine / Generator Rent, Gas Cylinder |

### J9. Labour Supply
| Type | Seed |
|---|---|
| Roles | Labour, Skilled Labour, Mukadam (Gang Leader) |
| Work-rate items | `L` Unskilled labour (day) · `L` Skilled labour (day) · `L` Supervisor (day) · `L` OT (hour) · `W` Loading / unloading (trip) · `W` Debris removal (trip) · `W` Cleaning (sq.ft) |
| Material items | Koi nahi |
| Templates | Monthly Labour Bill · Daily Labour Bill |
| Expense extra | Labour Transport, Labour Food |

### J10. Other
| Type | Seed |
|---|---|
| Roles | Sirf J0 ke common roles |
| Items | Koi item nahi. Admin apne items khud banayega |
| Templates | Blank Quotation (sirf default terms) |
