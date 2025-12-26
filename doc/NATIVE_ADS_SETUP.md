# Native Ads Setup Guide

This guide explains how to set up native ads in ad_flow, including the required platform-specific factory code.

## Overview

Native ads require you to create platform-specific factories that define how the ad should look. Unlike banner or interstitial ads, native ads give you full control over the ad's appearance.

## Step 1: Register Native Ad Factories

### Android (Kotlin)

Create a file `NativeAdFactories.kt` in your Android app:

```kotlin
// android/app/src/main/kotlin/com/yourapp/NativeAdFactories.kt

package com.yourapp

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.RatingBar
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.NativeAdFactory

/**
 * Small template - compact layout for lists
 */
class SmallNativeAdFactory(private val context: Context) : NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.native_ad_small, null) as NativeAdView

        // Headline (required)
        val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
        headlineView.text = nativeAd.headline
        adView.headlineView = headlineView

        // Body
        val bodyView = adView.findViewById<TextView>(R.id.ad_body)
        bodyView.text = nativeAd.body
        adView.bodyView = bodyView

        // Call to action
        val callToActionView = adView.findViewById<Button>(R.id.ad_call_to_action)
        callToActionView.text = nativeAd.callToAction
        adView.callToActionView = callToActionView

        // Icon
        val iconView = adView.findViewById<ImageView>(R.id.ad_icon)
        nativeAd.icon?.let {
            iconView.setImageDrawable(it.drawable)
            iconView.visibility = View.VISIBLE
        } ?: run {
            iconView.visibility = View.GONE
        }
        adView.iconView = iconView

        adView.setNativeAd(nativeAd)
        return adView
    }
}

/**
 * Medium template - standard layout with media
 */
class MediumNativeAdFactory(private val context: Context) : NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.native_ad_medium, null) as NativeAdView

        // Headline
        val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
        headlineView.text = nativeAd.headline
        adView.headlineView = headlineView

        // Body
        val bodyView = adView.findViewById<TextView>(R.id.ad_body)
        bodyView.text = nativeAd.body
        adView.bodyView = bodyView

        // Media view
        val mediaView = adView.findViewById<MediaView>(R.id.ad_media)
        adView.mediaView = mediaView

        // Call to action
        val callToActionView = adView.findViewById<Button>(R.id.ad_call_to_action)
        callToActionView.text = nativeAd.callToAction
        adView.callToActionView = callToActionView

        // Icon
        val iconView = adView.findViewById<ImageView>(R.id.ad_icon)
        nativeAd.icon?.let {
            iconView.setImageDrawable(it.drawable)
            iconView.visibility = View.VISIBLE
        } ?: run {
            iconView.visibility = View.GONE
        }
        adView.iconView = iconView

        // Advertiser
        val advertiserView = adView.findViewById<TextView>(R.id.ad_advertiser)
        nativeAd.advertiser?.let {
            advertiserView.text = it
            advertiserView.visibility = View.VISIBLE
        } ?: run {
            advertiserView.visibility = View.GONE
        }
        adView.advertiserView = advertiserView

        // Star rating
        val starRatingView = adView.findViewById<RatingBar>(R.id.ad_stars)
        nativeAd.starRating?.let {
            starRatingView.rating = it.toFloat()
            starRatingView.visibility = View.VISIBLE
        } ?: run {
            starRatingView.visibility = View.GONE
        }
        adView.starRatingView = starRatingView

        adView.setNativeAd(nativeAd)
        return adView
    }
}
```

### Android Layout XML

Create layout files in `android/app/src/main/res/layout/`:

**native_ad_small.xml:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<com.google.android.gms.ads.nativead.NativeAdView
    xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:background="@android:color/white"
    android:padding="8dp">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal">

        <ImageView
            android:id="@+id/ad_icon"
            android:layout_width="48dp"
            android:layout_height="48dp"
            android:scaleType="centerCrop"/>

        <LinearLayout
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:layout_marginStart="8dp"
            android:orientation="vertical">

            <TextView
                android:id="@+id/ad_headline"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:textSize="14sp"
                android:textStyle="bold"/>

            <TextView
                android:id="@+id/ad_body"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:textSize="12sp"
                android:maxLines="2"
                android:ellipsize="end"/>

        </LinearLayout>

        <Button
            android:id="@+id/ad_call_to_action"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textSize="12sp"/>

    </LinearLayout>

</com.google.android.gms.ads.nativead.NativeAdView>
```

**native_ad_medium.xml:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<com.google.android.gms.ads.nativead.NativeAdView
    xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:background="@android:color/white"
    android:padding="12dp">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical">

        <!-- Header row -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:layout_marginBottom="8dp">

            <ImageView
                android:id="@+id/ad_icon"
                android:layout_width="40dp"
                android:layout_height="40dp"
                android:scaleType="centerCrop"/>

            <LinearLayout
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:layout_marginStart="8dp"
                android:orientation="vertical">

                <TextView
                    android:id="@+id/ad_headline"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:textSize="16sp"
                    android:textStyle="bold"/>

                <TextView
                    android:id="@+id/ad_advertiser"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:textSize="12sp"
                    android:textColor="@android:color/darker_gray"/>

            </LinearLayout>

        </LinearLayout>

        <!-- Media -->
        <com.google.android.gms.ads.nativead.MediaView
            android:id="@+id/ad_media"
            android:layout_width="match_parent"
            android:layout_height="180dp"
            android:layout_marginBottom="8dp"/>

        <!-- Body -->
        <TextView
            android:id="@+id/ad_body"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textSize="14sp"
            android:maxLines="3"
            android:ellipsize="end"
            android:layout_marginBottom="8dp"/>

        <!-- Footer row -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:gravity="center_vertical">

            <RatingBar
                android:id="@+id/ad_stars"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                style="?android:attr/ratingBarStyleSmall"
                android:isIndicator="true"/>

            <View
                android:layout_width="0dp"
                android:layout_height="0dp"
                android:layout_weight="1"/>

            <Button
                android:id="@+id/ad_call_to_action"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"/>

        </LinearLayout>

    </LinearLayout>

</com.google.android.gms.ads.nativead.NativeAdView>
```

### Register Factories in MainActivity

```kotlin
// android/app/src/main/kotlin/com/yourapp/MainActivity.kt

package com.yourapp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register native ad factories
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "small_template",
            SmallNativeAdFactory(context)
        )

        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "medium_template",
            MediumNativeAdFactory(context)
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)

        // Unregister factories
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "small_template")
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "medium_template")
    }
}
```

---

### iOS (Swift)

Create `NativeAdFactories.swift` in your iOS Runner:

```swift
// ios/Runner/NativeAdFactories.swift

import Foundation
import google_mobile_ads

/// Small template - compact layout for lists
class SmallNativeAdFactory: FLTNativeAdFactory {
    func createNativeAd(_ nativeAd: GADNativeAd,
                        customOptions: [AnyHashable : Any]? = nil) -> GADNativeAdView? {
        
        let nibView = Bundle.main.loadNibNamed("SmallNativeAdView", owner: nil, options: nil)?.first
        guard let nativeAdView = nibView as? GADNativeAdView else {
            return nil
        }
        
        // Headline
        (nativeAdView.headlineView as? UILabel)?.text = nativeAd.headline
        
        // Body
        (nativeAdView.bodyView as? UILabel)?.text = nativeAd.body
        
        // Call to action
        (nativeAdView.callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)
        nativeAdView.callToActionView?.isUserInteractionEnabled = false
        
        // Icon
        (nativeAdView.iconView as? UIImageView)?.image = nativeAd.icon?.image
        nativeAdView.iconView?.isHidden = nativeAd.icon == nil
        
        nativeAdView.nativeAd = nativeAd
        return nativeAdView
    }
}

/// Medium template - standard layout with media
class MediumNativeAdFactory: FLTNativeAdFactory {
    func createNativeAd(_ nativeAd: GADNativeAd,
                        customOptions: [AnyHashable : Any]? = nil) -> GADNativeAdView? {
        
        let nibView = Bundle.main.loadNibNamed("MediumNativeAdView", owner: nil, options: nil)?.first
        guard let nativeAdView = nibView as? GADNativeAdView else {
            return nil
        }
        
        // Headline
        (nativeAdView.headlineView as? UILabel)?.text = nativeAd.headline
        
        // Body
        (nativeAdView.bodyView as? UILabel)?.text = nativeAd.body
        
        // Media
        nativeAdView.mediaView?.mediaContent = nativeAd.mediaContent
        
        // Call to action
        (nativeAdView.callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)
        nativeAdView.callToActionView?.isUserInteractionEnabled = false
        
        // Icon
        (nativeAdView.iconView as? UIImageView)?.image = nativeAd.icon?.image
        nativeAdView.iconView?.isHidden = nativeAd.icon == nil
        
        // Advertiser
        (nativeAdView.advertiserView as? UILabel)?.text = nativeAd.advertiser
        nativeAdView.advertiserView?.isHidden = nativeAd.advertiser == nil
        
        // Star rating
        (nativeAdView.starRatingView as? UIImageView)?.isHidden = nativeAd.starRating == nil
        
        nativeAdView.nativeAd = nativeAd
        return nativeAdView
    }
}
```

### iOS XIB Layout Files

Create XIB files using Xcode's Interface Builder:

1. In Xcode, right-click on `Runner` folder → New File → View
2. Name it `SmallNativeAdView.xib` and `MediumNativeAdView.xib`
3. Set the Custom Class of the root view to `GADNativeAdView`
4. Add UI elements and connect outlets:
   - `headlineView` → UILabel
   - `bodyView` → UILabel
   - `callToActionView` → UIButton
   - `iconView` → UIImageView
   - `mediaView` → GADMediaView (for medium template)
   - `advertiserView` → UILabel
   - `starRatingView` → UIImageView

### Register Factories in AppDelegate

```swift
// ios/Runner/AppDelegate.swift

import Flutter
import UIKit
import google_mobile_ads

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // Register native ad factories
        let pluginRegistrar = self.registrar(forPlugin: "io.flutter.plugins.googlemobileads")!
        
        FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
            pluginRegistrar,
            factoryId: "small_template",
            nativeAdFactory: SmallNativeAdFactory()
        )
        
        FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
            pluginRegistrar,
            factoryId: "medium_template",
            nativeAdFactory: MediumNativeAdFactory()
        )
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
```

---

## Step 2: Use in Flutter

```dart
import 'package:ad_flow/ad_flow.dart';

class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  final NativeAdManager _nativeManager = NativeAdManager();
  
  @override
  void initState() {
    super.initState();
    _loadAd();
  }
  
  Future<void> _loadAd() async {
    await _nativeManager.loadAd(
      factoryId: 'medium_template', // Must match registered factory ID
      onAdLoaded: (ad) => setState(() {}),
      onAdFailedToLoad: (error) {
        debugPrint('Native ad failed: ${error.message}');
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('My Content'),
        if (_nativeManager.isLoaded)
          SizedBox(
            height: 300, // Set appropriate height for your template
            child: AdWidget(ad: _nativeManager.nativeAd!),
          ),
      ],
    );
  }
  
  @override
  void dispose() {
    _nativeManager.dispose();
    super.dispose();
  }
}
```

---

## Factory ID Reference

| Factory ID | Description | Recommended Height |
|------------|-------------|-------------------|
| `small_template` | Compact layout for lists | 80-100dp |
| `medium_template` | Standard layout with media | 280-320dp |

---

## Troubleshooting

### "Platform exception: Native ad factory not found"

The factory ID in your Flutter code doesn't match any registered factory. Ensure:
1. Factory is registered in `MainActivity.kt` (Android) or `AppDelegate.swift` (iOS)
2. Factory ID matches exactly (case-sensitive)
3. App was rebuilt after adding native code (hot reload won't work)

### Native ad shows blank or doesn't render

1. Ensure layout XML (Android) or XIB (iOS) outlets are connected properly
2. Check that `nativeAdView.setNativeAd(nativeAd)` is called
3. Verify ad unit ID is valid and has native ads enabled

### App crashes on native ad load

1. Ensure `NativeAdView` is the root element of your layout
2. Check that all required views (headline, body, call-to-action) are present
3. Verify imports: `com.google.android.gms.ads.nativead.*` (Android)
