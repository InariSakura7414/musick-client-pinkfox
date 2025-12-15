# musick

A new Flutter project.

## Setup

### 1) Create `.env`

This app loads Supabase configuration from a local `.env` file (via `flutter_dotenv`).

Create/edit the file at the project root:

`.env`

And set:

- `SUPABASE_URL` (Supabase Project URL)
- `SUPABASE_ANON_KEY` (Supabase anon/public API key)

You can find these in the Supabase Dashboard:

Project Settings → API

Notes:

- `.env` is ignored by git (so keys aren’t committed).
- `.env` is bundled as a Flutter asset for runtime loading.

### 2) Install dependencies

Run:

`flutter pub get`

### 3) Run

Run:

`flutter run`

## Source layout (`lib/`)

- `lib/main.dart`
	- App entry point
	- Loads `.env`
	- Initializes Supabase
	- Starts the UI

- `lib/services/socket_service.dart`
	- TCP client for the EasyTCP server
	- Supports sending to arbitrary route IDs (e.g. route `1` for echo, route `10` for login/JWT)

- `lib/pages/connect_page.dart`
	- UI to connect to the TCP server (IP/port)

- `lib/pages/echo_page.dart`
	- Simple echo/chat UI
	- App bar title can be customized (used after login for `welcome! <userid>`)

- `lib/pages/supabase_auth_page.dart`
	- Supabase sign-in UI
	- Sends JWT to server via route `10`
	- Waits for server login JSON response and navigates to echo page on success

- `lib/pages/supabase_signup_page.dart`
	- Supabase sign-up UI
	- Returns to sign-in page after creating the account
