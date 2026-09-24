enum DirectTransferPhase {
  preparing,
  waitingForPeer,
  connecting,
  authenticating,
  sending,
  receiving,
  validating,
  complete,
  cancelled,
  error,
}

class DirectTransferState {
  final DirectTransferPhase phase;
  final String message;
  final double? progress;
  final String? peerName;

  const DirectTransferState({
    required this.phase,
    required this.message,
    this.progress,
    this.peerName,
  });

  const DirectTransferState.preparing()
    : this(
        phase: DirectTransferPhase.preparing,
        message: 'Preparing secure transfer…',
      );

  bool get isFinished =>
      phase == DirectTransferPhase.complete ||
      phase == DirectTransferPhase.cancelled ||
      phase == DirectTransferPhase.error;

  DirectTransferState copyWith({
    DirectTransferPhase? phase,
    String? message,
    double? progress,
    bool clearProgress = false,
    String? peerName,
  }) => DirectTransferState(
    phase: phase ?? this.phase,
    message: message ?? this.message,
    progress: clearProgress ? null : progress ?? this.progress,
    peerName: peerName ?? this.peerName,
  );
}
