# Stockmix

An offline Flutter inventory and cash-sales app using the supplied avocado, plum, linen, cement, maple, and rust palette. Android is the primary mobile target; the responsive web build also provides a convenient preview.

## Run

```sh
flutter pub get
flutter run
```

Start with an empty stock book. Set your store name and currency in **More → Store settings** before entering opening stock. Currency is locked after the first movement to preserve historical values.

For an isolated preview with in-memory sample data (nothing is written to your real stock book):

```sh
flutter run -d chrome --dart-define=DEMO=true
```

## Included

- Responsive dashboard, searchable inventory, prices, category and low-stock filters.
- Add/edit products, opening balances, cost/selling prices, units and alert thresholds.
- Barcode/QR camera lookup, image barcode scanning where supported, torch and manual fallback. Unknown codes can prefill a new item. Common numeric GTINs and GS1 Digital Link identifiers normalize for lookup; arbitrary links are never opened.
- Cash sale carts, explicit cash-received confirmation, integer-cent totals, and immutable price/cost snapshots. Completed sales deduct stock; unsuccessful or abandoned sales do not.
- Receipts, stock adjustments with reasons, optional record photos, and item movement history.
- Full stock counts with durable progress, stock-change freeze, complete-line validation, variance review and retained posted snapshots.
- Photo attachment from camera/gallery, compression off the native UI thread, maximum 1200px and 500KB JPEG output. JSON exports include those compressed photos.
- Durable transactional local storage: Sembast on mobile/desktop and IndexedDB on web. A failed commit rolls back in-memory changes. Browser storage is specific to the origin/browser profile.
- Daily activity, date filters, sales totals, stock JSON snapshots and CSV exports with spreadsheet formula escaping.
- Native file save/share menus. Available nearby targets can include Quick Share, AirDrop or Bluetooth, depending on the OS and receiving device. There is no custom Bluetooth or Wi-Fi Direct transport.
- JSON import with validation and duplicate-file rejection. Incoming files are saved as read-only records; adding products is a separate choice for stock snapshots in the same currency. Existing product IDs/barcodes are skipped, so import does not overwrite current balances or replay another store's sales.

## Sharing with another user

1. Open **More → Share & export** or use the export action in Stock or Records.
2. Choose Stock or Day record and select **Stockmix file** to include photos.
3. Tap **Share with another user** and choose a nearby-sharing target available on your device. Alternatively, save the file and transfer it yourself.
4. On the receiving device, save the JSON, open **More → Import a file**, and review it before importing.
5. Open **Received & saved records** to view imported copies.

CSV is for external spreadsheets and does not include images. JSON exports are capped at 30MB for import compatibility. Files are snapshots, not continuous synchronization. Stock import is not an exact full-database restore: local count drafts and previously received archives are not included in stock exports.

## Validation

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Tests cover ledger arithmetic, whole-sale stock validation, failed-write rollback, barcode uniqueness, historical price snapshots, stock count freezing and posting, database reopening, JSON round trips, duplicate import, existing-stock preservation, malformed exports, safe CSV, money parsing and phone/desktop navigation.

Camera/gallery hardware, permission denials, and nearby file transfer must additionally be checked on physical devices. iOS and macOS builds require a Mac. The Android debug APK is for testing, not store distribution; configure release signing before publishing.

## Scope relative to the supplied blueprint

The DOCX was treated as product reference material. This implementation covers the local stock, count, cash-sales and file-sharing workflows; it does not claim to implement the entire 77-screen roadmap.

Not included: hosted accounts, staff permissions or manager authentication, multi-device conflict reconciliation, server sync, encrypted application database, purchase orders/suppliers, branch transfers, lots/serials/expiry tracking, linked refunds, tax/discount configuration, payment processing, receipt OCR or cloud backup/restore. A manual return-restock adjustment adds inventory; it does not issue a refund. Records saved locally do not show a misleading cloud-synced status.

## Suggested next work

1. Receipt OCR with explicit review of extracted names, quantities and prices.
2. Full backup/restore, including count drafts and received records, with backup reminders.
3. Favorites, recent items and continuous barcode scanning for faster repeat sales.
4. A compare-and-accept screen for incoming stock changes, followed by authenticated synchronization.
5. Owner/staff roles with protected adjustments, linked refunds and approval history.

## Implementation references

- [Mobile Scanner](https://pub.dev/packages/mobile_scanner)
- [Native sharing through share_plus](https://pub.dev/packages/share_plus)
- [Image picker](https://pub.dev/packages/image_picker)
# stockmix
