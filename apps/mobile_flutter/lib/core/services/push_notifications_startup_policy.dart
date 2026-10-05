bool shouldPromptForPushPermissionAtStartup() => false;

bool shouldSyncPushTokenOnStartup({
  required bool firebaseReady,
  required String notificationPermission,
}) {
  return firebaseReady && notificationPermission == 'granted';
}
