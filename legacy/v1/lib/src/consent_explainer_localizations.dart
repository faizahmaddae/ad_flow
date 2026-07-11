// Copyright 2024 - AdMob Integration Package
// Pre-defined localizations for consent explainer dialogs
//
// Usage:
// ```dart
// import 'ads/ads.dart';
//
// AdFlow.instance.initializeWithExplainer(
//   context: context,
//   consentTexts: kPersianConsentExplainerTexts,
//   attTexts: kPersianATTExplainerTexts,
// );
// ```

import 'consent_explainer_dialog.dart';

// ============================================================================
// PERSIAN (FARSI) - فارسی
// ============================================================================

/// Persian (Farsi) texts for [ConsentExplainerDialog].
const kPersianConsentExplainerTexts = ConsentExplainerTexts(
  title: 'حریم خصوصی شما مهم است',
  description:
      'این برنامه رایگان است زیرا تبلیغات نمایش می‌دهد. '
      'برای حفظ رایگان بودن و بهبود تجربه شما، '
      'می‌خواهیم تبلیغات مرتبط با علایق شما نمایش دهیم.',
  benefitRelevantAds: 'تبلیغات مطابق با علایق شما',
  benefitDataSecure: 'اطلاعات شما امن می‌ماند',
  benefitKeepFree: 'کمک به رایگان ماندن برنامه',
  settingsHint: 'می‌توانید هر زمان تنظیمات را در بخش تنظیمات تغییر دهید.',
  continueButton: 'ادامه',
  skipButton: 'در صفحه بعد تصمیم می‌گیرم',
);

/// Persian (Farsi) texts for [ATTExplainerDialog].
const kPersianATTExplainerTexts = ATTExplainerTexts(
  title: 'اجازه ردیابی؟',
  description:
      'در صفحه بعد، اپل از شما می‌پرسد که آیا اجازه ردیابی می‌دهید. '
      'با انتخاب "اجازه"، به ما کمک می‌کنید تبلیغات مرتبط‌تری نمایش دهیم.',
  footnote: 'انتخاب شما تأثیری بر تعداد تبلیغات ندارد.',
  gotItButton: 'متوجه شدم',
);

// ============================================================================
// SPANISH - Español
// ============================================================================

/// Spanish texts for [ConsentExplainerDialog].
const kSpanishConsentExplainerTexts = ConsentExplainerTexts(
  title: 'Tu Privacidad Importa',
  description:
      'Esta aplicación es gratuita porque muestra anuncios. '
      'Para mantenerla gratuita y mejorar tu experiencia, '
      'nos gustaría mostrarte anuncios relevantes según tus intereses.',
  benefitRelevantAds: 'Anuncios que coinciden con tus intereses',
  benefitDataSecure: 'Tus datos permanecen seguros',
  benefitKeepFree: 'Ayuda a mantener la app gratuita',
  settingsHint:
      'Puedes cambiar tus preferencias en cualquier momento en Configuración.',
  continueButton: 'Continuar',
  skipButton: 'Decidiré en la siguiente pantalla',
);

/// Spanish texts for [ATTExplainerDialog].
const kSpanishATTExplainerTexts = ATTExplainerTexts(
  title: '¿Permitir Seguimiento?',
  description:
      'En la siguiente pantalla, Apple te preguntará si permites el seguimiento. '
      'Tocar "Permitir" nos ayuda a mostrarte anuncios más relevantes.',
  footnote: 'Tu elección no afectará la cantidad de anuncios que ves.',
  gotItButton: 'Entendido',
);

// ============================================================================
// HELPER: Get texts by language code
// ============================================================================

/// Returns [ConsentExplainerTexts] for the given language code.
///
/// Supported codes: 'en', 'fa', 'es'
/// Returns English (default) for unsupported codes.
///
/// Example:
/// ```dart
/// final texts = getConsentTextsForLanguage('es');
/// ```
ConsentExplainerTexts getConsentTextsForLanguage(String languageCode) {
  switch (languageCode.toLowerCase()) {
    case 'fa':
    case 'per':
    case 'fas':
      return kPersianConsentExplainerTexts;
    case 'es':
    case 'spa':
      return kSpanishConsentExplainerTexts;
    case 'en':
    case 'eng':
    default:
      return kDefaultConsentExplainerTexts;
  }
}

/// Returns [ATTExplainerTexts] for the given language code.
///
/// Supported codes: 'en', 'fa', 'es'
/// Returns English (default) for unsupported codes.
///
/// Example:
/// ```dart
/// final texts = getATTTextsForLanguage('fa');
/// ```
ATTExplainerTexts getATTTextsForLanguage(String languageCode) {
  switch (languageCode.toLowerCase()) {
    case 'fa':
    case 'per':
    case 'fas':
      return kPersianATTExplainerTexts;
    case 'es':
    case 'spa':
      return kSpanishATTExplainerTexts;
    case 'en':
    case 'eng':
    default:
      return kDefaultATTExplainerTexts;
  }
}

/// Returns both consent and ATT texts for the given language code.
///
/// Example:
/// ```dart
/// final (consentTexts, attTexts) = getExplainerTextsForLanguage('es');
///
/// AdFlow.instance.initializeWithExplainer(
///   context: context,
///   consentTexts: consentTexts,
///   attTexts: attTexts,
/// );
/// ```
(ConsentExplainerTexts, ATTExplainerTexts) getExplainerTextsForLanguage(
  String languageCode,
) {
  return (
    getConsentTextsForLanguage(languageCode),
    getATTTextsForLanguage(languageCode),
  );
}
