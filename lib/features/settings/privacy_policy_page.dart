import 'package:flutter/material.dart';
import 'package:stockmix/core/theme/design.dart';

void showPrivacyPolicyDialog(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
  );
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & Data Policy'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            // Header highlight card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: avocado.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: avocado.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: avocado,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Private Business Records',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: avocado,
                                  ),
                            ),
                            Text(
                              'On-Device Storage · Transparent Advertising',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.stockMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Stockmix keeps your inventory, prices, sales, and photos strictly on your physical device. We operate no cloud databases and do not collect your business records. To keep the app free, Stockmix displays privacy-compliant advertisements via Google AdMob.',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            const Eyebrow('Core Privacy Principles'),
            const SizedBox(height: 12),

            _buildSection(
              context,
              icon: Icons.cloud_off_rounded,
              title: 'No Cloud Servers or Accounts',
              content:
                  'Stockmix requires no sign-up, email, password, or profile. All data stays in your device’s private sandbox database.',
            ),

            _buildSection(
              context,
              icon: Icons.campaign_outlined,
              title: 'Advertising (Google AdMob)',
              content:
                  'Stockmix is supported by native advertising from Google Mobile Ads (AdMob). The AdMob SDK may process pseudonymous device identifiers (such as Google Advertising ID), approximate IP location, and ad interaction telemetry for fraud detection, frequency capping, and ad delivery. Your store and inventory records are NEVER linked or sent to AdMob.',
            ),

            _buildSection(
              context,
              icon: Icons.camera_alt_outlined,
              title: 'Camera & Photo Permissions',
              content:
                  'Camera access is used in-memory solely for barcode scanning, receipt QR lookup, and optional product photos. Photos and video frames are never sent off-device.',
            ),

            _buildSection(
              context,
              icon: Icons.memory_rounded,
              title: 'On-Device Text Recognition',
              content:
                  'Google ML Kit OCR processes product packaging text entirely locally on your device CPU/GPU. No images or text are transmitted to Google.',
            ),

            _buildSection(
              context,
              icon: Icons.sync_alt_rounded,
              title: 'User-Initiated Sharing',
              content:
                  'Data is shared only when you explicitly export JSON/CSV files or use direct, encrypted peer-to-peer sync (Nearby or QR stream).',
            ),

            _buildSection(
              context,
              icon: Icons.delete_outline_rounded,
              title: 'Data Ownership & Deletion',
              content:
                  'You own all your records. You can delete items individually or clear all data by wiping the app storage or uninstalling the app.',
            ),

            const SizedBox(height: 16),

            const Eyebrow('Compliance & Standards'),
            const SizedBox(height: 12),

            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBullet(
                    'Apple App Store Privacy Labels:',
                    'Business records: "Data Not Collected". Advertising: Device ID and diagnostics used for third-party advertising via Google AdMob.',
                  ),
                  const SizedBox(height: 8),
                  _buildBullet(
                    'Google Play Data Safety Policy:',
                    'Contains Ads declared. Device/other IDs and ad interaction diagnostics declared for advertising and fraud prevention via Google Play Services.',
                  ),
                  const SizedBox(height: 8),
                  _buildBullet(
                    'GDPR & CCPA Compliant:',
                    'Full rights to access, rectification, portability, and erasure. Ad choices and consent handled per Google AdMob standards.',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Center(
              child: Text(
                'Version 1.0.0 · Stockmix (com.bertoxic.stockmix)',
                style: TextStyle(fontSize: 12, color: context.stockMuted),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'stockmix.help@gmail.com',
                style: TextStyle(fontSize: 12, color: avocado, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Surface(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: context.stockInk),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    content,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.stockMuted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBullet(String boldPrefix, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.4),
              children: [
                TextSpan(
                  text: '$boldPrefix ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
