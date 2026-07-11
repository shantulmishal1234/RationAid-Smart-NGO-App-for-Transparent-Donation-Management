<h1 align="center">
  <br>
  <img src="assets/images/app_logo.png" alt="Ration Aid Logo" width="120">
  <br>
  <strong>Ration Aid</strong>
  <br>
</h1>

<h4 align="center">
  A <strong>Flutter-based NGO Management Platform</strong> that bridges donors, families, purchasers, distributors, and administrators — digitizing the entire humanitarian aid lifecycle from donation to doorstep delivery.
</h4>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Dart-SDK_^3.10-0175C2?style=for-the-badge&logo=dart&logoColor=white" />
  <img src="https://img.shields.io/badge/Firebase-Firestore_%7C_Auth_%7C_FCM-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" />
  <img src="https://img.shields.io/badge/Version-1.0.0-brightgreen?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Platform-Android_%7C_iOS-lightgrey?style=for-the-badge&logo=android&logoColor=white" />
</p>

<p align="center">
  <a href="#-overview">Overview</a> •
  <a href="#-key-features">Features</a> •
  <a href="#-user-roles">Roles</a> •
  <a href="#-architecture">Architecture</a> •
  <a href="#-tech-stack">Tech Stack</a> •
  <a href="#-project-structure">Structure</a> •
  <a href="#-data-models">Models</a> •
  <a href="#-testing">Testing</a> •
  <a href="#-getting-started">Setup</a>
</p>

---

## 📖 Overview

**Ration Aid** is a comprehensive Final Year Project (FYP) built using Flutter and Firebase, designed for NGOs that manage ration-based humanitarian aid. The platform digitizes and streamlines every step of the humanitarian supply chain:

> _From a donor's first pledge → to verification → procurement → warehouse stocking → delivery assignment → GPS-tracked doorstep delivery → proof of delivery — all managed in a single, role-aware mobile application._

Traditional NGO aid distribution is paper-heavy, error-prone, and lacks real-time transparency. Ration Aid solves this by providing:

- **Transparent donation tracking** with 11 real-time status stages
- **AI-informed family scoring** with multi-reviewer quorum approvals
- **Smart procurement workflows** with dual-approval gates
- **GPS-enabled last-mile delivery** with offline proof-of-delivery sync
- **Live reports & analytics** with exportable PDF and CSV outputs
- **Immutable audit trails** across every financial and operational action

---

## ✨ Key Features

### 🏠 Household & Family Management
- Register families with rich demographic profiles (household size, children details, widow status, housing condition, asset ownership)
- Multi-phase geolocation capture — unverified field entry → admin GPS verification
- Privacy-masking for donor-facing views (neighborhood shown, exact address hidden)
- Category tagging: `Food`, `Medicine`, or `Combined` assistance types
- Family need tracking per item (quantities + units), updated as donations come in

### 💰 Donation Engine
- Dual donation types: **In-Kind** (physical goods) and **Monetary** (cash/transfer)
- 11-state donation lifecycle: `Draft → Under Verification → Verified → Pending Assignment → Stocked → In Process → Out for Delivery → Delivered → Closed`
- Donor-facing family discovery with need-gap visibility
- Real-time donation tracking screen with status timeline
- Donation success confirmations and rejection handling
- Donor profile setup and onboarding flow

### 🧑‍⚖️ Multi-Layer Approval Workflow
- **Family Review**: Quorum-based multi-reviewer approval system with configurable threshold
- **Final Approver Gate**: A designated final authority reviews quorum results before a family is marked accepted
- **Purchase Approval**: Admin verifies procurement requests before purchase execution
- **Delivery Verification**: Admin verifies completed deliveries against proof-of-delivery evidence

### 🛒 Procurement & Inventory
- Purchaser portal to raise procurement requests linked to donation/warehouse needs
- Inbound pickup tracking for in-kind donations collected from donors
- Warehouse stock management with inventory issue reporting
- Master ledger system recording every financial movement across donation pools (GRF pool, In-Kind pool)
- Immutable pool transfer records and ledger audit entries

### 🚚 Last-Mile Delivery (GPS-Enabled)
- Distributor dashboard with assigned deliveries and status pipeline
- Full delivery map powered by **Flutter Map** with live route visualization
- Step-by-step status transitions: `Not Started → Picked Up → In Transit → Delivered / Failed`
- **Proof of Delivery (PoD)** with photo upload via Cloudinary
- **Offline PoD Queue**: If connectivity is lost, proofs are saved locally and auto-synced when internet is restored (via `connectivity_plus` background listener)
- Failure reporting with structured reasons: `Family Unavailable`, `Address Incorrect`, `Safety Concern`, `Other`
- Smart routing service using GPS coordinates

### 📊 Reports & Analytics
- **Donations Report**: Filterable by date range, status, type; exportable to PDF/CSV
- **Family Statistics Report**: Demographic breakdowns, acceptance rates, geographic distribution
- **HRM Report**: Member-level activity and role summaries
- **Purchasing Report**: Procurement cost analysis, vendor summaries
- All reports rendered with interactive **fl_chart** visualizations
- One-tap PDF generation and CSV export

### 🔔 Notification System
- Firebase Cloud Messaging (FCM) for push notifications
- In-app local notification handling via `flutter_local_notifications`
- Per-user notification feed with read/unread tracking
- Role-targeted notifications (e.g., admin alerts for new donations, distributor alerts for delivery assignments)

### 🎨 Theme & UX
- Full **Light / Dark mode** toggle with persistent preference via `shared_preferences`
- Google Fonts (Poppins) typography throughout
- Custom native splash screen with `flutter_native_splash`
- Custom app launcher icon via `flutter_launcher_icons`
- Smooth Material 3 color scheme: Primary `#5CB9DD` · Accent `#6DD1A1`

---

## 👥 User Roles

The app is role-driven. After login, the **Dashboard Router** reads the user's assigned role(s) from Firestore and redirects accordingly.

| Role | Dashboard | Capabilities |
|---|---|---|
| **Donor** | `DonorDashboard` | Browse families, create donations (In-Kind/Monetary), track donation status, manage profile |
| **Admin / NGO Admin** | `AdminDashboard` | Full system access — families, donations, procurement, delivery, HRM, reports, audit trail |
| **Purchaser** | `PurchaserDashboard` | Raise procurement requests, manage inbound pickups, update purchase records |
| **Distributor** | `VolunteerDashboard` | View assigned deliveries, update delivery status, submit proof of delivery via GPS map |
| **Volunteer** | `VolunteerDashboard` | Assist with deliveries and field operations |

> Roles are stored as a `List<String>` in the Firestore `users` collection. A user may hold multiple roles (e.g., `['admin', 'ngo_admin']`).

---

## 🏗️ Architecture

Ration Aid follows a **feature-first, service-layer architecture** with clear separation of concerns:

```
┌─────────────────────────────────────────────────────┐
│                    Presentation Layer                │
│    Screens  ·  Widgets  ·  Dashboards  ·  Dialogs   │
├─────────────────────────────────────────────────────┤
│                   Business Logic Layer               │
│          Services  ·  Providers  ·  Utils            │
├─────────────────────────────────────────────────────┤
│                      Data Layer                      │
│         Models  ·  Firebase  ·  Cloud Firestore      │
├─────────────────────────────────────────────────────┤
│                  Infrastructure Layer                │
│    Firebase Auth  ·  FCM  ·  Cloudinary  ·  GPS     │
└─────────────────────────────────────────────────────┘
```

### Design Patterns Used
- **Service Layer Pattern** — all Firestore/API calls encapsulated in dedicated `*_service.dart` files
- **Provider Pattern** — `ThemeProvider` uses `ChangeNotifier` for global state propagation
- **Repository-like Models** — each model has `fromFirestore()` and `toFirestore()` serialization
- **Role-Based Dashboard Routing** — `DashboardRouter` fetches user roles from Firestore and navigates accordingly
- **Offline-First Queue** — delivery proofs stored locally and batch-synced when connectivity resumes

---

## 🛠️ Tech Stack

### Core Framework
| Technology | Version | Purpose |
|---|---|---|
| **Flutter** | SDK ^3.10.0 | Cross-platform UI framework |
| **Dart** | ^3.10.0 | Primary programming language |

### Backend & Database
| Package | Version | Purpose |
|---|---|---|
| `firebase_core` | ^3.6.0 | Firebase app initialization |
| `firebase_auth` | ^5.3.1 | User authentication (email/password) |
| `cloud_firestore` | ^5.4.4 | NoSQL real-time database |
| `firebase_messaging` | ^15.1.3 | Push notifications (FCM) |

### UI & Fonts
| Package | Version | Purpose |
|---|---|---|
| `google_fonts` | ^6.3.2 | Poppins typography |
| `fl_chart` | ^1.1.1 | Interactive charts in reports |
| `flutter_local_notifications` | ^17.2.1+2 | In-app notification display |

### Maps & Location
| Package | Version | Purpose |
|---|---|---|
| `flutter_map` | ^6.1.0 | OpenStreetMap-based delivery maps |
| `latlong2` | ^0.9.0 | Coordinate handling |
| `geolocator` | ^10.1.0 | Device GPS positioning |

### Storage & Files
| Package | Version | Purpose |
|---|---|---|
| `image_picker` | ^1.1.0 | Camera/gallery for proof-of-delivery |
| `file_picker` | ^10.3.10 | Document selection |
| `path_provider` | ^2.1.1 | Local file system access |
| `shared_preferences` | ^2.2.2 | Theme preference persistence |

### Export & Reports
| Package | Version | Purpose |
|---|---|---|
| `pdf` | ^3.10.8 | PDF report generation |
| `open_file` | ^3.3.2 | Open generated PDFs |
| `csv` | ^6.0.0 | CSV data export |

### Networking & Utilities
| Package | Version | Purpose |
|---|---|---|
| `http` | ^1.2.0 | HTTP requests (Cloudinary uploads) |
| `connectivity_plus` | ^6.0.4 | Network state monitoring |
| `url_launcher` | ^6.3.2 | External URL and map links |
| `intl` | ^0.18.1 | Date/time formatting & localization |
| `uuid` | ^4.5.1 | Unique ID generation |
| `fluttertoast` | ^9.0.0 | Toast notifications |
| `permission_handler` | ^11.0.1 | Runtime permission requests |

### Dev & Testing
| Package | Purpose |
|---|---|
| `flutter_native_splash` | Native splash screen generation |
| `flutter_launcher_icons` | App icon generation |
| `fake_cloud_firestore` | Firestore mock for unit tests |
| `firebase_auth_mocks` | Auth mock for unit tests |
| `mocktail` | General mocking framework |
| `integration_test` | End-to-end integration testing |

---

## 📁 Project Structure

```
ration_aid/
├── lib/
│   ├── main.dart                          # App entry, theme setup, routing, offline sync listener
│   ├── firebase_options.dart              # Firebase platform config (generated)
│   ├── models/                            # Data models with Firestore serialization
│   │   ├── assistance_pack_model.dart     # Ration pack templates
│   │   ├── delivery_assignment_model.dart # Delivery lifecycle (7 status states)
│   │   ├── donation_model.dart            # Donation lifecycle (11 status states)
│   │   ├── family_model.dart              # Full family profile (demographics, needs, review)
│   │   ├── family_review_model.dart       # Reviewer decisions per family
│   │   ├── inbound_pickup_model.dart      # In-Kind donation pickup records
│   │   ├── master_ledger_model.dart       # Financial ledger entries
│   │   ├── nav_step_model.dart            # Delivery navigation steps
│   │   ├── notification_model.dart        # In-app notification records
│   │   ├── procurement_model.dart         # Purchase request records
│   │   └── warehouse_stock_model.dart     # Warehouse inventory tracking
│   ├── providers/
│   │   └── theme_provider.dart            # Light/Dark mode state (ChangeNotifier)
│   ├── services/                          # Business logic & Firestore operations
│   │   ├── allocation_service.dart        # Family-to-donation matching logic
│   │   ├── assistance_pack_service.dart   # Ration pack CRUD
│   │   ├── audit_service.dart             # Immutable audit log writer
│   │   ├── auth_service.dart              # Firebase Auth login/register/logout
│   │   ├── cloudinary_service.dart        # Image upload to Cloudinary CDN
│   │   ├── delivery_service.dart          # Full delivery pipeline + offline PoD sync
│   │   ├── donation_service.dart          # Donation CRUD and status transitions
│   │   ├── family_review_service.dart     # Quorum review logic
│   │   ├── family_service.dart            # Family CRUD
│   │   ├── favorites_service.dart         # Donor family favorites
│   │   ├── final_approval_service.dart    # Final approver gate logic
│   │   ├── funding_service.dart           # GRF pool / In-Kind pool financial engine
│   │   ├── hrm_service.dart               # Human resource member management
│   │   ├── inventory_service.dart         # Warehouse inventory operations
│   │   ├── ledger_service.dart            # Master ledger read/write
│   │   ├── notification_service.dart      # FCM + local notification management
│   │   ├── procurement_service.dart       # Procurement request workflows
│   │   ├── receipt_service.dart           # Receipt generation
│   │   ├── report_csv_service.dart        # CSV export logic
│   │   ├── report_pdf_service.dart        # PDF report generation
│   │   └── routing_service.dart           # GPS delivery routing logic
│   ├── screens/
│   │   ├── dashboard_router.dart          # Role-based navigation hub
│   │   ├── donor_dashboard.dart           # Donor home screen
│   │   ├── purchaser_dashboard.dart       # Purchaser home screen
│   │   ├── volunteer_dashboard.dart       # Distributor/Volunteer home screen
│   │   ├── Startup & Authentication/
│   │   │   ├── splash_screen.dart         # Native splash with logo
│   │   │   ├── auth_screen.dart           # Login + Sign-up (tabbed, with strength meter)
│   │   │   └── Onboarding_Screen.dart     # First-launch onboarding slides
│   │   ├── Admin/
│   │   │   ├── admin_dashboard.dart
│   │   │   ├── AssistancePacks/           # Ration pack template management
│   │   │   ├── Delivery/                  # Admin delivery oversight & reassignment
│   │   │   ├── Donation Section/          # Admin donation detail and approval
│   │   │   ├── FamilyReview/              # Multi-reviewer quorum dashboard
│   │   │   ├── FinalApprover/             # Final accept/reject gate
│   │   │   ├── House Hold Section/        # Full family registry management
│   │   │   ├── HRM(members)/              # NGO staff management
│   │   │   ├── Verification/              # Purchase approval + inventory issues
│   │   │   ├── Audit Trail/               # System-wide immutable audit log
│   │   │   ├── Notifications/             # Admin notification center
│   │   │   └── Reports&Analytics/         # 4 report types with charts + export
│   │   ├── Donor/
│   │   │   ├── profile_setup_screen.dart  # First-login donor profile setup
│   │   │   ├── Donation/                  # Create, track, and view donations
│   │   │   └── Family/                    # Browse and select beneficiary families
│   │   ├── Distributor/
│   │   │   ├── distributor_dashboard.dart
│   │   │   └── Delivery/                  # GPS map, PoD upload, failure report
│   │   └── Purchaser/
│   │       └── screens/                   # Purchase entry + inbound pickup
│   ├── theme/                             # Theme tokens and constants
│   ├── utils/                             # Shared utility functions
│   └── widgets/                           # Reusable UI components
│
├── test/
│   ├── unit/
│   │   ├── models/                        # 7 model serialization tests
│   │   └── services/                      # 4 service logic tests
│   └── widget/                            # Widget rendering tests
│
├── integration_test/                      # 3 end-to-end flow tests
│   ├── auth_flow_test.dart
│   ├── donation_flow_test.dart
│   └── delivery_flow_test.dart
│
├── assets/images/                         # App logo & splash images
├── firestore.rules                        # Firestore security rules
├── firestore.indexes.json                 # Composite index definitions
├── firebase.json                          # Firebase project configuration
└── pubspec.yaml                           # Dart package manifest
```

---

## 📐 Data Models

### `Donation` — 11-State Lifecycle
```
Draft → Under Verification → Verified → Pending Assignment
     → Stocked → In Process → Out for Delivery → Delivered → Closed
                                                            → Rejected
```

### `DeliveryAssignment` — 7-State Pipeline
```
Not Started → Picked Up → In Transit → Delivered → Admin Verified
                                     → Failed → Reassigned
```

### `Family` — Rich Profile with 4-Phase Data

| Phase | Fields |
|---|---|
| **Core** | Name, city, area, family size, adults, children, needs map, status |
| **Demographics** | Husband name, widow status, house status/condition/size, biography, assets, electronics |
| **Location** | Unverified GPS → verified GPS, address, verifier identity & timestamp |
| **Review** | Reviewer IDs, approve/reject counts, quorum threshold, final approver decision |
| **Funding** | Target amount, raised amount, pending amount, remaining amount |
| **Assignment** | Assigned pack ID/name, delivery status tracking |

### `ProcurementModel`
Tracks vendor, items list with quantities/costs, linked donation, approval status, timestamps, and the approving admin.

### `MasterLedger`
Every credit/debit across the GRF (General Relief Fund) pool and In-Kind pool is recorded as an immutable ledger entry with full metadata.

### `WarehouseStock`
Tracks item quantities, units, last updated timestamp, and linked procurement for full inventory traceability.

---

## 🔐 Security (Firestore Rules)

The app enforces strict Firestore security rules with role-based access control:

| Collection | Read | Write |
|---|---|---|
| `donations` | Owner or Admin | Owner (draft only) / Admin |
| `families` | Any authenticated user | Admin only |
| `master_ledger` | Admin only | Admin only |
| `master_ledger_audit` | Admin only | Immutable — no update/delete |
| `pool_transfers` | Admin only | Immutable — no update/delete |
| `users` | Own profile or Admin | Admin (limited self-update allowed) |
| `notifications` | Own notifications only | Owner update / No delete |
| `procurement_requests` | Admin only | Admin only |
| `audit_logs` | Admin only | Immutable — no update/delete |

> **All collections not explicitly listed default to DENY.**

---

## 🧪 Testing

The project has a comprehensive three-tier testing strategy:

### Unit Tests — `test/unit/`

**Model Tests** (7 files) validate serialization/deserialization:
- `DonationModel` — all 11 status states, field mappings
- `DeliveryAssignmentModel` — 7 status enums, failure reasons
- `AssistancePackModel` — pack template fields
- `MasterLedgerModel` — financial entry integrity
- `NotificationModel` — notification payload structure
- `ProcurementModel` — purchase request fields
- `WarehouseStockModel` — inventory snapshot validation

**Service Tests** (4 files) use `fake_cloud_firestore` and `firebase_auth_mocks`:
- `AuthService` — login, registration, error handling
- `AllocationService` — donation-to-family matching logic
- `DeliveryService` — status transitions and PoD sync
- `ThemeProvider` — theme persistence behavior

### Widget Tests — `test/widget/`
Core UI widget behavior and rendering validation.

### Integration Tests — `integration_test/` (3 flows)
End-to-end flows run on a real device or emulator:
- **Auth Flow** — splash → onboarding → login → role-based routing
- **Donation Flow** — donor dashboard → family selection → create donation → success
- **Delivery Flow** — distributor login → delivery detail → GPS map → proof of delivery

### Running Tests

```bash
# Unit & Widget tests
flutter test

# Specific integration test (requires connected device/emulator)
flutter test integration_test/auth_flow_test.dart
flutter test integration_test/donation_flow_test.dart
flutter test integration_test/delivery_flow_test.dart
```

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) ≥ 3.10.0
- Dart SDK ≥ 3.10.0
- Android Studio / VS Code with Flutter extension
- A Firebase project with **Authentication**, **Firestore**, and **FCM** enabled
- A [Cloudinary](https://cloudinary.com/) account for image uploads (proof of delivery)

### 1. Clone the Repository
```bash
git clone <repository-url>
cd ration_aid
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Configure Firebase
1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Enable **Email/Password** authentication
3. Create a **Cloud Firestore** database
4. Enable **Firebase Cloud Messaging**
5. Run the FlutterFire CLI to generate `firebase_options.dart`:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

### 4. Deploy Firestore Rules & Indexes
```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

### 5. Generate Splash Screen & App Icons
```bash
dart run flutter_native_splash:create
dart run flutter_launcher_icons
```

### 6. Run the App
```bash
# Debug mode
flutter run

# Release build (Android APK)
flutter build apk --release

# Release build (iOS)
flutter build ios --release
```

---

## 🗺️ Donation Lifecycle Flow

```
Donor              Admin             Purchaser        Distributor
  │                  │                   │                 │
  ├─ Create Donation │                   │                 │
  │  (Draft)         │                   │                 │
  │────────────────→ │                   │                 │
  │  Under Review    │                   │                 │
  │  ← Admin Reviews ┤                   │                 │
  │    Verified      │                   │                 │
  │                  ├─ Assign to Family │                 │
  │                  │  Pending Assign.  │                 │
  │                  │ ───────────────→  │                 │
  │                  │  In-Kind: Pickup  │                 │
  │                  │  Stocked (WH)     │                 │
  │                  ├─ Create Delivery ─┼───────────────→ │
  │                  │  Out for Delivery │                 │
  │                  │                   │                 ├─ GPS Navigate
  │                  │                   │                 ├─ Submit PoD
  │                  │ ◄─────────────────┼─────────────── ┤
  │                  │  Delivered         │                 │
  │                  ├─ Admin Verify PoD │                 │
  │ ◄────────────────┤  Closed           │                 │
  │  Donation Done   │                   │                 │
```

---

## 📸 App Screens Overview

| Module | Key Screens |
|---|---|
| **Auth** | Splash Screen, Onboarding (3 slides), Login/Signup with password strength meter |
| **Donor** | Profile Setup, Family Browser, Create Donation Wizard, Donation Tracker (live timeline) |
| **Admin** | Dashboard Hub, Family Registry, Add/Edit Family, Quorum Review Board, Final Approver Gate, Pack Management, Delivery Oversight, Procurement Approval, Reports (4 types), Audit Trail, HRM |
| **Distributor** | Delivery Queue, GPS Map View, Proof of Delivery Camera, Failure Report |
| **Purchaser** | Purchase Entry Form, Inbound Pickup Management |

---

## 🤝 Contributing

This project is a Final Year Project (FYP). Contributions, suggestions, and feedback are welcome.

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m 'Add: your feature description'`
4. Push to the branch: `git push origin feature/your-feature`
5. Open a Pull Request

---

## 📄 License

This project is developed as an academic Final Year Project. All rights reserved by the author.

---

## 👤 Author

**Uzair Ahmad**  
Final Year Project — Computer Science

---

<p align="center">
  Made with ❤️ using <strong>Flutter</strong> & <strong>Firebase</strong>
  <br>
  <em>Empowering NGOs · Connecting Donors · Reaching Families</em>
</p>
