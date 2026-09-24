import 'package:flutter/material.dart';
import 'package:stockmix/core/theme/design.dart';
import '../domain/transfer_state.dart';

/// Shared host/join flow. Progress reflects transport events, not a timer.
class SyncProgressView extends StatelessWidget {
  final DirectTransferState state;
  final Widget? pairingCode;
  final bool canMerge;
  final bool merging;
  final VoidCallback onMerge;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  const SyncProgressView({
    super.key,
    required this.state,
    this.pairingCode,
    required this.canMerge,
    required this.merging,
    required this.onMerge,
    required this.onCancel,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final complete = state.phase == DirectTransferPhase.complete;
    final failed = state.phase == DirectTransferPhase.error;
    final cancelled = state.phase == DirectTransferPhase.cancelled;
    final pairing =
        state.phase == DirectTransferPhase.preparing ||
        state.phase == DirectTransferPhase.waitingForPeer;
    final stage = switch (state.phase) {
      DirectTransferPhase.preparing ||
      DirectTransferPhase.waitingForPeer ||
      DirectTransferPhase.connecting ||
      DirectTransferPhase.authenticating => 0,
      DirectTransferPhase.sending || DirectTransferPhase.receiving => 1,
      _ => 2,
    };
    final title = merging
        ? 'Merging your records…'
        : failed
        ? 'Sync interrupted'
        : cancelled
        ? 'Sync cancelled'
        : complete
        ? (canMerge ? 'Records received' : 'All done')
        : pairing
        ? (pairingCode != null
              ? 'Connect the other phone'
              : 'Finding your other phone…')
        : stage == 0
        ? 'Connecting securely…'
        : stage == 1
        ? 'Exchanging records…'
        : 'Saving your records…';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Eyebrow('Two-way sync'),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: Text(
            title,
            key: ValueKey(title),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: 24),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          child: pairing && pairingCode != null
              ? Surface(
                  key: const ValueKey('pair'),
                  child: Column(
                    children: [
                      pairingCode!,
                      const SizedBox(height: 16),
                      const Text(
                        'On the other phone, choose Join sync and scan this code.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : SizedBox(
                  key: ValueKey(
                    merging
                        ? 'merge'
                        : state.isFinished
                        ? 'result'
                        : 'transfer',
                  ),
                  height: 180,
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (!state.isFinished || merging)
                          SizedBox(
                            width: 124,
                            height: 124,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: maple,
                              backgroundColor: context.stockLine,
                            ),
                          ),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: .75, end: 1),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutBack,
                          builder: (context, scale, child) =>
                              Transform.scale(scale: scale, child: child),
                          child: Icon(
                            merging
                                ? Icons.call_merge_rounded
                                : failed
                                ? Icons.error_outline_rounded
                                : cancelled
                                ? Icons.close_rounded
                                : complete
                                ? Icons.check_circle_rounded
                                : Icons.sync_alt_rounded,
                            size: 64,
                            color: failed
                                ? context.stockRust
                                : complete && !merging
                                ? context.stockPositive
                                : context.stockInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 24),
        if (!failed && !cancelled && !merging)
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: complete || i <= stage
                                ? maple
                                : context.stockLine,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ['Connect', 'Exchange', 'Save'][i],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: i == stage
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 24),
        Semantics(
          liveRegion: true,
          child: Text(
            state.message,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.stockMuted, height: 1.5),
          ),
        ),
        if (!state.isFinished && state.progress != null) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: state.progress!.clamp(0, 1)),
          const SizedBox(height: 6),
          Text(
            '${(state.progress!.clamp(0, 1) * 100).round()}% of current transfer',
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 28),
        if (merging)
          const Text(
            'Applying records to this store…',
            textAlign: TextAlign.center,
          )
        else if (complete && canMerge) ...[
          const Text(
            'Your copy is saved. Merge it into this store now, or find it later in Received & saved records.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onMerge,
            icon: const Icon(Icons.call_merge_rounded),
            label: const Text('Merge now'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onDone,
            icon: const Icon(Icons.bookmark_outline),
            label: const Text('Save for later merge'),
          ),
        ] else if (state.isFinished)
          FilledButton(
            onPressed: onDone,
            child: Text(failed || cancelled ? 'Back to sharing' : 'Done'),
          )
        else ...[
          const Text(
            'Keep both phones nearby and Stockmix open.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onCancel, child: const Text('Cancel sync')),
        ],
      ],
    );
  }
}
