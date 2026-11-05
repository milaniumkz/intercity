/// Native screens additionally retry on app resume; no external polling.
Stream<void> networkRecoveryEvents() => const Stream<void>.empty();
