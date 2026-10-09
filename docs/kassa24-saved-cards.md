# Saved card ride payments (web)

Official contracts:

- https://business.kassa24.kz/documentation/instructions-for-working-with-card-tokens
- https://business.kassa24.kz/documentation/examples-of-creating-transactions-with-tokens
- https://business.kassa24.kz/documentation/sending-a-request
- https://business.kassa24.kz/documentation/description-of-response-field-values-from-the-online-payments-system
- https://business.kassa24.kz/documentation/cancellation-of-payment

Kassa24 support must enable card tokens and supply the merchant's `acquiringId`. The documentation specifies amounts in tiyn (KZT). RUB automatic charges are disabled until a provider with a confirmed RUB contract is integrated; cash and manual transfers remain available.

Configure existing `KASSA24_LOGIN`/`KASSA24_PASSWORD` securely on the VPS, `BACKEND_PUBLIC_URL` (including `/api`) and `PUBLIC_WEB_URL`. Use a strong stable `JWT_SECRET` of at least 32 characters or a dedicated `KASSA24_TOKEN_ENCRYPTION_KEY` of that length. Rotating the encryption secret requires rebinding existing cards. Real ride payments require `KASSA24_DEMO=false`; demo charges never credit real driver wallets.

After support confirmation, set `kassa24AcquiringId` to the terminal number and `kassa24SavedCardsEnabled` to `true` in admin Settings. Alternatively use environment variables `KASSA24_ACQUIRING_ID` and `KASSA24_SAVED_CARDS_ENABLED`. The feature stays unavailable while prerequisites are missing. Never put credentials in admin Settings or chat.

Passengers bind a card through Kassa24's hosted form in Profile → Payment methods. Only a server-encrypted opaque token, token hash, customer identifier and last four digits are retained. Full card numbers and CVV are never stored or sent to the app. Authenticated provider token listing is the source of card ownership; callback bodies cannot create cards or acknowledge a charge.

A passenger explicitly chooses **Bank card** for an order. Existing `CARD_TRANSFER` orders retain their manual-transfer meaning. The chosen card is snapshotted onto the order; money is not charged when the order is created or when the driver arrives. The transition to `IN_PROGRESS` creates an immutable fare payment, processed by a durable reconciliation worker.

Each of up to three attempts has a unique provider `orderId`. A connection loss or processing status rechecks the same ID, never starts another charge or switches to cash while its outcome is unknown. Only a confirmed final failure (or a rejected creation request with no previous transaction) advances to another attempt. After the third failure, the payment method changes to cash, with realtime, push and localized female voice notices for both parties. Browser audio still requires browser permission/user interaction; the order button and driver's online action prime audio.

Authenticated status must match merchant, order, fare amount and live/demo mode before accepting it. Payment callbacks only wake reconciliation. Completed paid trips credit driver earnings once under a payment row lock; the existing service commission is charged separately. Cancelled orders reconcile/cancel their provider transactions and confirm refunds before recording them.

Validation uses a local PostgreSQL database and a mocked provider. Never perform real test charges against passenger cards. `VPS Ops → status → payment-config` reports configuration presence and an authenticated read-only status probe without exposing values.
