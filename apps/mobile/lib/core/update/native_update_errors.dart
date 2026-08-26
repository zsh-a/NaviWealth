enum NativeUpdateFailure {
  installPermission,
  download,
  integrity,
  packageMismatch,
  install,
  unsupported,
}

final class NativeUpdateException implements Exception {
  const NativeUpdateException(this.failure, {this.cause});

  final NativeUpdateFailure failure;
  final Object? cause;

  @override
  String toString() => 'NativeUpdateException($failure)';
}
