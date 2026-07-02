/// Legacy Finance form barrel.
///
/// Domain-neutral form primitives now live in `core/forms/`; this file remains
/// as a compatibility export for the historical FinanceOS slices that still
/// consume account / security entry widgets from `features/shared`.
library;

export '../../../core/forms/forms.dart';
export 'account_picker.dart';
export 'manual_security_sheet.dart';
export 'symbol_field.dart';
