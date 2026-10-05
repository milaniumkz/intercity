# admin_web

Flutter web admin client for INTERCITY operations.

## Runtime Configuration

The app uses the same shared API configuration strategy as `mobile_flutter`:

```bash
export INTERCITY_API_BASE_URL="https://your-api-host.example/api"
```

If the variable is absent, the app falls back to the safe placeholder
`https://api.intercity.invalid/api`. Production-like environments should always
override it explicitly.

## Local Checks

```bash
/Volumes/PD1000/job/flutter/bin/flutter pub get
/Volumes/PD1000/job/flutter/bin/flutter analyze
/Volumes/PD1000/job/flutter/bin/flutter test
/Volumes/PD1000/job/flutter/bin/flutter build web
```

Or run the shared verification script from repository root:

```bash
bash /Volumes/PD1000/job/INTERCITY/scripts/verify_flutter_apps.sh
```

The script auto-detects the local Flutter SDK path used in this workspace and
falls back to `flutter` from `PATH` in CI or on other machines.

## Notes

- Auth refresh logic is hardened against recursive refresh and multi-refresh
  races.
- Keep generated local outputs such as `build/` and `.dart_tool/` out of version
  control.
