# Browse

Browse is a SwiftUI macOS browser experiment with AI-assisted briefing and page chat features.

## Requirements

- macOS 15 or newer
- Xcode with Swift 6 support

## Development

Open `Package.swift` in Xcode and run the `Browse` executable target.

From the command line:

```sh
swift test
```

## API Keys

Briefings and page chat require user-provided API keys:

- Claude API key for synthesis and chat
- Exa API key for briefing search

Add keys in the app's Settings window. Keys are stored only in the current user's macOS Keychain under the app service name `com.browse.app.api-keys.v2`.

The app uses non-interactive Keychain reads so macOS should not show password prompts during launch, briefing, or chat. If Keychain access would require a password prompt, the app treats the key as unavailable and asks the user to configure it again.

No API keys, signing identities, local usernames, certificates, or machine-specific paths should be committed to this repository.
