import 'package:flutter/material.dart';

import '../../../core/account/animewitcher_account_models.dart';
import '../../../core/utils/localized_text.dart';

String localizedAnimeWitcherAccountError(
  BuildContext context,
  Object error,
) {
  if (error is! AnimeWitcherAccountException) {
    return appText(
      context,
      english: 'The operation could not be completed. Try again.',
      arabic: 'تعذر إكمال العملية. حاول مرة ثانية.',
    );
  }

  final isArabic =
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';
  if (!isArabic) return error.message;
  return switch (error.code) {
    'email-already-in-use' => 'يوجد حساب مسجل بهذا البريد.',
    'invalid-credentials' => 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
    'email-not-verified' => 'لم يتم التحقق من البريد الإلكتروني بعد.',
    'verification-cooldown' =>
      'يمكنك طلب رسالة تفعيل جديدة بعد مرور 60 ثانية.',
    'weak-password' => 'يجب أن تحتوي كلمة المرور على 6 أحرف على الأقل.',
    'untrusted-email-domain' => 'استخدم بريد Gmail أو Outlook أو Yahoo.',
    'invalid-email' => 'أدخل بريدًا إلكترونيًا صحيحًا.',
    'same-email' => 'هذا هو البريد الإلكتروني الحالي بالفعل.',
    'user-disabled' => 'تم تعطيل هذا الحساب.',
    'too-many-attempts' => 'محاولات كثيرة. حاول لاحقًا.',
    'google-not-configured' => 'دخول Google غير مهيأ لهذه النسخة.',
    'google-token-missing' => 'لم يُرجع Google رمز دخول صالحًا.',
    'wrong-google-account' =>
      'اختر حساب Google نفسه لتأكيد هويتك.',
    'unsupported-sign-in-provider' =>
      'طريقة تسجيل الدخول الحالية لا تدعم هذه العملية.',
    'recent-login-required' =>
      'يلزم تأكيد هويتك من جديد قبل إكمال العملية.',
    'provider-already-linked' => 'كلمة المرور مضافة إلى هذا الحساب بالفعل.',
    'account-email-missing' => 'تعذر قراءة البريد الإلكتروني للحساب.',
    'not-configured' => 'مزامنة AnimeWitcher غير مهيأة لهذه النسخة.',
    'storage-not-configured' => 'رفع صور الحساب غير مهيأ لهذه النسخة.',
    'storage-permission-denied' =>
      'رفض AnimeWitcher رفع صورة الحساب.',
    'invalid-image' => 'اختر صورة صالحة.',
    'image-too-large' => 'الصورة المحددة كبيرة جدًا.',
    'image-download-url-missing' =>
      'تم رفع الصورة لكن تعذر الحصول على رابطها.',
    'image-upload-failed' => 'تعذر رفع صورة الحساب. حاول مرة ثانية.',
    'bio-too-long' => 'يجب ألا تتجاوز النبذة 200 حرف.',
    'country-too-long' => 'يجب ألا يتجاوز اسم الدولة 30 حرفًا.',
    'invalid-birth-year' =>
      'أدخل سنة ميلاد صحيحة بين 1970 و2020.',
    'birth-year-locked' => 'لا يمكن تغيير سنة الميلاد بعد حفظها.',
    'account-banned' => 'تم إيقاف حساب AnimeWitcher هذا.',
    'duplicate-user-documents' =>
      'يوجد تكرار قديم في بيانات الحساب. تواصل مع دعم AnimeWitcher.',
    'permission-denied' => 'رفض خادم AnimeWitcher العملية.',
    'invalid-session' || 'not-signed-in' =>
      'انتهت جلسة الحساب. سجل الدخول من جديد.',
    'invalid-user-name' =>
      'يجب أن يتكون اسم المستخدم من 5 إلى 25 حرفًا.',
    'profile-not-found' => 'لم يتم العثور على ملف حساب AnimeWitcher.',
    'account-not-found' => 'لم يتم العثور على الحساب.',
    'sync-failed' || 'network-or-server-error' || 'email-sync-failed' =>
      'تعذّر الاتصال بخادم AnimeWitcher. حاول مرة ثانية.',
    _ => error.message,
  };
}

void showAnimeWitcherAccountMessage(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : null,
      ),
    );
}
