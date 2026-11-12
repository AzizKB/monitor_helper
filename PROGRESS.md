# Monitor Helper beta progress

Last updated: 12 November 2026, Asia/Kuwait.

This checkpoint saves the work from 11–12 November 2026 for the upcoming second beta test. The app remains native SwiftUI. The collector was not changed, and this checkpoint has not been uploaded to TestFlight.

## Current decisions

- Continue enhancing and testing the current iOS app before the next TestFlight release.
- Revisit migration to Flutter after the upcoming beta test, with the intention of using Flutter for future iOS and Android development. No Flutter migration, SDK installation or Android implementation has started.
- Preserve the existing Supabase backend, account approval gate and collector behavior.
- Treat application and node visibility as filtering; do not delete historical inventory records.

## Charts and dashboard controls

- Fetch the full selected chart window instead of truncating to a limited number of recent points.
- Use 1-minute chart intervals for 15M, 30M, 1H and 3H; use 10-minute intervals for 6H, 12H and 24H.
- Align 10-minute intervals to the clock. At 11:32, the latest completed interval ends at 11:30 and represents 11:20–11:30. The next completed interval ends at 11:40.
- Keep the requested time domain visible, show window boundaries and interval labels, and break chart lines across missing intervals instead of inserting zeros or drawing through gaps.
- Weight response-time averages using sum/count when available. Calls/errors remain averages of the original rate samples.
- Retain the peak original sample value and timestamp in aggregated chart data. The displayed peak is a peak 1-minute sample, not an uncollected raw maximum.
- Guard against stale asynchronous responses replacing newer chart selections.
- Add range pickers inside both dashboard detail screens, bound to the shared selection. Match the existing dashboard button style, including the iOS toolbar treatment.

## Application and node visibility

- Hide applications absent from collector inventory for more than two calendar months, using `last_seen_at` with `created_at` fallback. This supersedes the initial six-month application rule.
- Show only nodes with a CPU, memory or availability metric observed within the last 65 minutes. This final live-node rule applies to every application and supersedes the intermediate two-month node rule.
- Use the shared, RLS-aware `v_live_monitor_nodes` view for backend node lists and totals.
- Use `get_monitor_applications_v2` to return explicit reporting-node counts. Totals represent visible live nodes, rather than all historical nodes.
- Apply the same 65-minute filter to cached nodes and infrastructure details in the frontend.
- Preserve an intentionally empty refreshed node result instead of falling back to old initial nodes.
- Counts such as CRM and SOA are dynamic; do not hard-code the counts observed during testing.

## Authentication experience

- Rebuild Sign In and Request Access with labeled fields, input validation, clear loading states and accessible notices.
- Add show/hide controls for password and confirmation fields, with automatic hiding when the app becomes inactive.
- Show live password guidance: at least 12 characters, uppercase and lowercase letters, a number and an allowed symbol; enforce the backend's 72-byte maximum.
- Apply new-password rules during signup/reset without blocking existing users from signing in with their existing password.
- Add confirmation-code verification and resend flows using eight-digit codes, a 60-second resend cooldown and a 15-minute code lifetime.
- Add Forgot Password, code verification, new-password entry and completion screens.
- Keep recovery credentials in memory and separate from the monitoring session. Password recovery does not bypass administrator approval.
- Add friendly messages for incorrect credentials, invalid email, weak/mismatched passwords, expired codes, rate limits and network failures. Avoid displaying raw backend responses or tokens.
- Preserve the email entered on Sign In when opening verification or recovery. The sheet request captures the email and whether a code has already been sent.
- Keep the Remember Email preference and iOS password-manager integration. Remove the disabled future SSO placeholder.
- Support the actual top-level session response returned by signup, alongside unconfirmed-account responses.
- Remove response-body previews from decoding errors to avoid exposing authentication tokens.
- Keep pending approval and access-check retry screens clear and separate from monitoring access.

## Email and live Auth configuration

These settings were saved in the existing Supabase project through its dashboard; committing this repository does not apply dashboard settings automatically.

- Email signup and confirmation remain enabled. Administrator approval remains required for monitoring data.
- Minimum password length is 12, with the existing uppercase/lowercase/digit/symbol requirements and leaked-password protection retained.
- Email OTP length remains eight digits; expiry is 900 seconds.
- SMTP uses the existing Brevo relay. The owner replaced the SMTP credential manually; no SMTP key is stored in this repository.
- Sender display name is Monitor Helper. Confirmation and recovery subjects/content were updated.
- Exact email template sources are saved in `supabase/auth-emails/confirm-signup.html` and `supabase/auth-emails/reset-password.html`.
- Signup and recovery emails reached the designated test mailbox. Signup verification succeeded, and the account remained pending approval. Password sign-in was checked; reset-code verification reached new-password entry, and the owner reported that the reset test worked.
- Delivery follow-up: the first verification email reached Spam. Brevo currently uses a free Gmail sender, rewrites its address, and has no authenticated custom sending domain configured. Configure an owner-controlled sender domain and retest placement before wider beta invitations. Inbox delivery is not guaranteed by the successful SMTP test.

## Database migration history

The November migrations below were applied during this week's work and are saved in chronological order:

1. `20261111082222_add_full_window_chart_series.sql`
2. `20261111085610_align_chart_clock_intervals.sql`
3. `20261111092312_hide_applications_unseen_for_six_months.sql`
4. `20261111092921_hide_applications_unseen_for_two_months.sql`
5. `20261111095227_hide_nodes_unseen_for_two_months.sql`
6. `20261111095847_show_only_recently_reporting_nodes.sql`

Earlier local migration files for cleanup cadence, admin observability and six-hour infrastructure retention are included unchanged as historical SQL sources. They predate this week's work. Do not rerun cleanup or retention migrations merely to restore this checkpoint; inspect the target database's migration history first.

## Verification completed

- All 23 unit tests across five suites passed after the final authentication email-prefill fix.
- The iOS Release build succeeded. The only reported build warning was skipped App Intents metadata extraction because the app has no AppIntents dependency.
- The signed Debug app was installed and checked in the iPhone 18 Pro simulator.
- Manual checks covered friendly incorrect-password messaging, password visibility, signup requirements, email verification, pending approval, sign-out/sign-in, recovery-code delivery and verification, and the corrected recovery email prefill.
- Hosted unit tests avoid starting live authentication/API tasks.
- `git diff --check` passed before this checkpoint.

## Resume here

1. Address the authenticated Brevo sending domain and repeat delivery checks with an authorized test mailbox.
2. Continue user-led review of the current SwiftUI beta and record any remaining issues.
3. Before TestFlight upload, confirm the next unused build number, signing configuration and archive. No version/build bump or upload is part of this checkpoint.
4. After the upcoming beta feedback, revisit the Flutter migration decision and scope before starting a separate implementation.

The project currently declares marketing version 1.0 and build 2. Local build logs and review screenshots are temporary artifacts outside the repository; the test coverage, migration SQL, email templates and this handoff note are the durable checkpoint.
