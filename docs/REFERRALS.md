# Invitations

Passenger and driver profiles show the personal invitation link, the number of registered invitees, and earned bonuses separately in KZT and RUB. Current links use `PUBLIC_WEB_URL`; the retired Firebase address falls back to the production web address.

The invitation page saves the code and opens registration. Once registration succeeds, it opens the download page. The user installs the app and signs in with the same phone/password, so attribution lives in the account and does not depend on App Store installation tracking. Direct visits to the download page without a login return to registration.

In admin settings use the App Store / Google Play shortcuts to configure `appStoreUrl` and `googlePlayUrl` with the actual HTTPS listing URLs. Downloads are displayed only when these values exist; no listing URL is invented. Registration and the web app remain available.

`referralCommissionPercent` controls the bonus for each inviter, as a percentage of the service commission (default 25%). Completing city and intercity rides credits the inviter of the passenger and the inviter of the driver. No commission means no referral bonus. Credits use the ride currency and are committed atomically with the completed status, with wallet locking to prevent duplicate awards. Registration itself increments the invitee count; it does not award a trip bonus.

Backend tests: `npm run build && node --test test/*.test.js`. Set `CURRENCY_TEST_DATABASE_URL` to the isolated local `127.0.0.1/intercity_currency_test` database to run the registration, financial, and concurrency integration cases.
