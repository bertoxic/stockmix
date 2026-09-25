import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:stockmix/core/ads/ad_service.dart';
import 'package:stockmix/core/theme/design.dart';

/// A compact Native Ad widget styled to blend seamlessly with the Stockmix UI
/// curves, typography, and palette (both light and dark modes) while adhering strictly
/// to Google AdMob Native Ad policies.
///
/// Features:
/// - Uses a custom Android layout [stockmixNativeAd] with a compact, pill-shaped Call-To-Action button (small width, non-stretched).
/// - Ultra-compact height (~68dp), barely ~1/4 of the dashboard hero card height.
/// - Matches Stockmix's signature 24px surface curves, border lines, and color palette.
/// - CTA button matches Stockmix FilledButton (plum in light, avocado in dark).
/// - Gracefully collapses to [SizedBox.shrink] on non-mobile platforms or when offline.
class NativeAdCard extends StatefulWidget {
  /// Layout type: defaults to [TemplateType.small] for minimal height on non-Android platforms.
  final TemplateType templateType;

  /// Optional custom margin around the ad card.
  final EdgeInsetsGeometry? margin;

  /// Optional override for the Ad Unit ID. Defaults to [AdService.nativeAdUnitId].
  final String? adUnitId;

  const NativeAdCard({
    super.key,
    this.templateType = TemplateType.small,
    this.margin,
    this.adUnitId,
  });

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _nativeAd;
  bool _isAdLoaded = false;
  Brightness? _lastBrightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_lastBrightness == null) {
      _lastBrightness = brightness;
      _loadAd(brightness);
    } else if (_lastBrightness != brightness) {
      _lastBrightness = brightness;
      // Reload ad to update colors when theme changes between light & dark
      _loadAd(brightness);
    }
  }

  void _loadAd(Brightness brightness) {
    if (!AdService.isSupported) return;

    _nativeAd?.dispose();
    _nativeAd = null;
    _isAdLoaded = false;

    final isDark = brightness == Brightness.dark;

    // Palette matched directly to Stockmix design system tokens
    final backgroundColor = isDark ? darkPaper : paper;
    final primaryTextColor = isDark ? linen : plum;
    final secondaryTextColor = isDark ? darkMuted : muted;
    final ctaBackgroundColor = isDark ? avocado : plum;
    final ctaTextColor = isDark ? plum : paper;

    final nativeAd = NativeAd(
      adUnitId: widget.adUnitId ?? AdService.nativeAdUnitId,
      factoryId: Platform.isAndroid ? 'stockmixNativeAd' : null,
      customOptions: {'isDark': isDark},
      nativeAdOptions: NativeAdOptions(
        adChoicesPlacement: AdChoicesPlacement.topRightCorner,
      ),
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[NativeAdCard] Ad failed to load: ${error.message} (code ${error.code})');
          ad.dispose();
          if (mounted) {
            setState(() {
              _isAdLoaded = false;
              _nativeAd = null;
            });
          }
        },
      ),
      nativeTemplateStyle: !Platform.isAndroid
          ? NativeTemplateStyle(
              templateType: widget.templateType,
              mainBackgroundColor: backgroundColor,
              cornerRadius: 24.0, // Matches Stockmix 24px surface curves
              callToActionTextStyle: NativeTemplateTextStyle(
                textColor: ctaTextColor,
                backgroundColor: ctaBackgroundColor,
                style: NativeTemplateFontStyle.bold,
                size: 11.0,
              ),
              primaryTextStyle: NativeTemplateTextStyle(
                textColor: primaryTextColor,
                style: NativeTemplateFontStyle.bold,
                size: 13.0,
              ),
              secondaryTextStyle: NativeTemplateTextStyle(
                textColor: secondaryTextColor,
                style: NativeTemplateFontStyle.normal,
                size: 11.0,
              ),
              tertiaryTextStyle: NativeTemplateTextStyle(
                textColor: secondaryTextColor,
                style: NativeTemplateFontStyle.normal,
                size: 10.0,
              ),
            )
          : null,
    );

    _nativeAd = nativeAd;
    nativeAd.load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    _nativeAd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdService.isSupported || !_isAdLoaded || _nativeAd == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? darkPaper : paper;
    final borderColor = isDark ? darkLine : line;

    // Custom layout on Android is ~68dp, compact small template on iOS is ~90dp
    final isSmall = widget.templateType == TemplateType.small;
    final height = Platform.isAndroid ? 68.0 : (isSmall ? 90.0 : 320.0);

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Container(
        margin: widget.margin ?? const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: AdWidget(ad: _nativeAd!),
          ),
        ),
      ),
    );
  }
}
