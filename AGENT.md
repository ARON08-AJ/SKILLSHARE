# Agent Memory & Workflow Guidelines

## Core Directives

1. **GitHub Commit and Push (MANDATORY)**
   - Always commit all changes to git and push them to the GitHub repository: `https://github.com/ARON08-AJ/SKILLSHARE.git` on branch `main`.
   - Never stop after making file edits without staging (`git add`), committing with a descriptive commit message (`git commit`), and pushing (`git push origin main`).
   - Always verify that `git status` reports `working tree clean` and the remote branch is up to date.

2. **Codebase Verification (MANDATORY)**
   - Run `flutter analyze` after completing code modifications to guarantee zero errors or warnings before committing.

## Key System Architectures

### 1. Delivery Partner: Order Decline & Re-assignment
- When an order is declined by a partner, it reverts to status `'confirmed'` and adds the partner's UID to `declinedPartnerIds`.
- The order immediately reappears in the `Available` tab for other delivery partners, but remains hidden for any partner whose UID is in `declinedPartnerIds`.
- The seller receives an instant in-app notification of the decline.

### 2. Role-Based "Edit Profile" Dynamic Dispatch
- Never open a generic or mismatched form. The edit profile action must always route dynamically based on role:
  - **Skilled Person**: `SkilledUserSetupScreen` (Skills, Hourly Rate, Experience, Portfolio, Bio, Aadhaar).
  - **Customer**: `CustomerSetupScreen` (Name, Phone, Address, Bio, Interests, Services Needed — NO government ID required).
  - **Company**: `CompanySetupScreen` (Company Name, Industry, CIN / MSME, GST, Headquarters, Website, Description).
  - **Delivery Partner**: `DeliveryProfileScreen` (Vehicle Type, Vehicle Reg Number, Driving License / ID Number, Operating City, ID Upload).

### 3. Customer Verification Exemption
- Customer accounts are strictly exempt from mandatory document / government ID verification.
- Never show ID verification blockers or document upload prompts to customers.

### 4. Delivery Partner Onboarding & Verification Restrictions
- On signup, delivery partners route to `DeliveryProfileScreen` in setup mode to submit profile details and upload their driving license / government ID to Cloudinary (`delivery_verification` folder).
- Delivery partners are strictly blocked from viewing or accepting orders until their verification status is `'approved'` by the Admin.
- If unverified, `DeliveryScreen` displays a real-time status card (Pending Review / Action Required / Declined with rejection reason) and directs them to their profile.
- `FirestoreService.assignDeliveryPartner` enforces this check on the backend.

### 5. Admin Panel: Pending Requests & Detailed Verification Modal
- `AdminScreen` loads pending verification requests across all 3 roles: Delivery Partners, Skilled Persons, and Companies.
- Clicking any record or the "Review Verification Details" button opens `_VerificationDetailsDialog`.
- The dialog shows registration info, role-specific attributes, and uploaded identification documents.
- Document previews feature a tap-to-zoom modal (`_DocumentImageViewerDialog`) with `InteractiveViewer` for pinch-to-zoom inspection.
- "Approve Verification" and "Decline" (with rejection reason input) actions are located inside the detailed modal.
- Approving or rejecting updates all corresponding collections (`users`, `skilled_users`, `company_profiles`) and dispatches an in-app notification to the user.

### 6. App Lock System (Pattern & Numeric PIN)
- **Zero-Biometrics**: Biometric and fingerprint lock options are completely disabled and removed per user requirements.
- **Lock Methods**:
  - **PIN Lock (Number)**: 4 to 6 digit numeric code entered via interactive `PinKeypadView` with animated dot indicators, haptic feedback, and auto-submit.
  - **Pattern Lock**: Interactive 3x3 dot grid (`PatternLockView`) with custom gesture tracing, line connections, collinear dot auto-connection, haptic feedback, and error shake.
- **Cold Start & Lifecycle Protection**:
  - `AppLockConfig` is preloaded in `main()` before `runApp()`, ensuring `appLockProvider.sessionUnlocked = false` immediately when enabled so no child widgets/screens flash on app launch.
  - `AppLockGate` keeps underlying child completely `Offstage` while locked to prevent data leaks or touch interactions, and uses `PopScope(canPop: false)` to prevent bypassing with the Android back button.
  - `didChangeAppLifecycleState` listens for `paused`, `hidden`, and `inactive` lifecycle states and calls `lockNow()` so returning to the app from background/app switcher always demands unlock.


