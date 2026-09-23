import 'package:flutter/widgets.dart';
import 'generated/app_localizations.dart';
export 'generated/app_localizations.dart' show AppLocalizations;

/// Convenient access: `context.l10n.todaysSales`
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Maps a stored category value (as saved on Item records, e.g. "Soft Drinks")
/// to its localized display label. The underlying stored/filtered value is
/// never changed — only what's shown on screen.
String localizedCategory(AppLocalizations l10n, String category) {
  switch (category) {
    case 'Soft Drinks':
      return l10n.categorySoftDrinks;
    case 'Snacks':
      return l10n.categorySnacks;
    case 'Dairy':
      return l10n.categoryDairy;
    case 'Chocolates':
      return l10n.categoryChocolates;
    case 'Biscuits':
      return l10n.categoryBiscuits;
    case 'Noodles':
      return l10n.categoryNoodles;
    case 'Chips':
      return l10n.categoryChips;
    case 'Personal Care':
      return l10n.categoryPersonalCare;
    case 'Stationery':
      return l10n.categoryStationery;
    case 'Cleaning Items':
      return l10n.categoryCleaningItems;
    case 'Grocery':
      return l10n.categoryGrocery;
    case 'Others':
      return l10n.categoryOthers;
    default:
      return category;
  }
}

/// Maps a stored payment-mode code ('cash' | 'upi' | 'card' | 'credit' | 'mixed')
/// to its localized display label. Falls back to the raw code (uppercased)
/// for any unrecognized value.
String localizedPaymentMode(AppLocalizations l10n, String mode) {
  switch (mode.toLowerCase()) {
    case 'cash':
      return l10n.cash;
    case 'upi':
      return l10n.upi;
    case 'card':
      return l10n.card;
    case 'credit':
      return l10n.credit;
    case 'mixed':
      return l10n.mixed;
    default:
      return mode.toUpperCase();
  }
}
