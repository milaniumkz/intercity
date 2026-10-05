class PreparedPaymentWindow {
  Future<bool> open(String url) async => false;

  Future<void> close() async {}
}

PreparedPaymentWindow? preparePaymentWindow() => null;
