# Chat notifications and completed-trip rating

City/intercity messages are persisted before notifying the other participant. Authenticated `/realtime/me/stream` events and FCM carry trip/message identifiers and generic text. Public realtime streams exclude user events. Push failures never undo saved messages.

The app deduplicates foreground FCM, realtime and polling by trip/message ID. Initial history and outgoing messages are silent. Foreground notifications use app audio once; background notifications depend on browser/OS permission. Notification links open the corresponding trip/chat. The production build includes the supplied public Firebase VAPID key; private Firebase credentials stay server-side.

On intercity completion, the passenger is prompted to rate 1–5 and can return through history. Only the owner can rate a completed trip with a selected driver. Duplicate submissions are rejected under a database lock. Ratings 1–2 require an explanation and administrator review, matching the city policy. Repeated moderation decisions cannot double-count the rating.

Validation includes private recipient/push-failure checks, PostgreSQL ownership/status/duplicate/moderation tests, Flutter notification dedup/history tests and completed-trip rating submission tests. Actual background delivery still depends on the user's device and notification permission.
