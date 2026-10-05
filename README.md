# Ebb

Mail that ebbs away: keeps your inbox from ever filling up.

> Ebb permanently deletes email. Preview first with a dry run (`ebb scan`, or
> Preview in the menu bar): it lists what would be removed and changes nothing.

## Install

```bash
brew install --cask nspxmiguel/tap/ebb
```

The cask compiles Ebb on this Mac (about a minute). No signed binary is
shipped, so Gatekeeper does not prompt.

### From source

Requires macOS 14 or later and Xcode Command Line Tools.

```bash
git clone https://github.com/NspxMiguel/Ebb.git && cd Ebb && ./build.sh
```

The app lands at `build/Ebb.app`. The CLI is bundled as
`build/Ebb.app/Contents/Helpers/ebb`.

## Features

- Two cleanup ages: disposable mail (verification codes, newsletters) expires in
  1 hour by default; everything else in 1 day (up to 30 days configurable)
- Starred messages (Gmail) and flagged messages (iCloud) are never deleted
- Gmail Important folder is never deleted
- "Summarize what matters" button: inline summaries of your 50 newest inbox
  messages (powered by Apple Intelligence on macOS 26+, or Groq's free API with
  your own key)
- Delete everything, with typed confirmation
- Gmail and iCloud presets, plus any IMAP server
- Menu bar app and `ebb` CLI sharing the same accounts
- Portuguese and English (`EBB_LANG=pt` or `EBB_LANG=en`)

## Setting up an account

Use the menu bar app or `ebb add`. The username is the IMAP login; the password
must be an app password, not the account password.

**Gmail.** Turn on 2-Step Verification, then create an app password at
[myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords).
Username is the full Gmail address.

**iCloud.** Create an app-specific password at
[account.apple.com](https://account.apple.com) under Sign-In and Security.
Username is the Apple ID.

Any other provider: `ebb add custom <username> --host <imap-host>` (port 993
and TLS by default).

## What counts as disposable

Disposable mail expires in a shorter age (default 1 hour) and can be toggled on
or off per kind:

**Verification codes.** One-time login codes and verification codes (subject
phrases like "verification code", "código de verificação", "confirm your",
"confirme seu", "código de acceso", or patterns like "123456 is your…"). Never
tracking codes or promotional codes.

**Bulk mail.** Messages with `List-Unsubscribe` or `List-Id` headers, or with
`Precedence: bulk`, `list`, or `junk`. This includes most automated notifications
(GitHub issues, CI alerts, newsletters, status pages).

Each kind can be turned off independently: `ebb set <account> --codes off`
or `ebb set <account> --bulk off`.

The cleanup check interval (how often Ebb scans the mailbox) is separate from
message age: a shorter check interval means more frequent scans, not younger
expiry.

## Summaries

The "Summarize what matters" button fetches a summary of your 50 newest inbox
messages without marking them as read.

**Apple Intelligence (preferred).** On macOS 26 with Apple Intelligence enabled,
summaries run entirely on your Mac. Nothing leaves the device.

**Groq API (fallback).** If Apple Intelligence is unavailable, Ebb uses Groq's
free API. You provide your own API key from [console.groq.com/keys](https://console.groq.com/keys).
Ebb sends the sender, subject line, date, and first ~400 characters of the
newest 50 messages. Your key stays in the macOS keychain and never leaves the
device except for the API request.

## How deletion works

**Gmail.** Scans All Mail, Spam, and Trash only. Candidates are moved to Trash.
When permanent deletion is on, those messages are then emptied from Trash.

**iCloud and other IMAP servers.** Every folder except Drafts. Candidates are
flagged `\Deleted` and expunged. If the server defers expunge (typical on
iCloud while another client has the folder open), the run reports them as
pending and the next run retries.

When permanent deletion is off, messages only go to Trash and the provider's
own retention applies.

## Safety

- Starred (Gmail) and flagged (iCloud) messages are kept by default
- Drafts are never touched, and neither are `Notes` folders (Apple Notes and
  Gmail store notes as IMAP messages)
- When a server lists a folder with a SPECIAL-USE flag (`\Trash`, `\Sent`, …),
  that flag decides the folder's role; names are only a fallback
- Per-folder exclusions
- Dry run: `ebb scan`
- Delete-everything requires typing the account username (app) or passing
  `--yes-delete-everything` (CLI)
- Passwords live only in the macOS keychain
- `~/Library/Application Support/Ebb/accounts.json` holds no secrets
- The only network traffic is IMAP over TLS to the mail provider

## CLI reference

`<account>` is the username, the account UUID, or the 8-character short id
shown by `ebb accounts`. Passwords are read from stdin, never from an argument.

The app and the CLI are separate binaries, so the first time one of them reads a
password the other one saved, macOS asks for keychain access; choose
"Always Allow".

| Command | Description | Example |
| --- | --- | --- |
| `accounts` | List saved accounts | `ebb accounts` |
| `add` | Add an account; password from stdin | `security find-generic-password -s <service> -w \| ebb add icloud you@icloud.com` |
| `remove` | Remove an account | `ebb remove you@icloud.com` |
| `inbox` | List the newest inbox messages | `ebb inbox you@gmail.com` |
| `mailboxes` | List folders (role and skip markers) | `ebb mailboxes you@icloud.com` |
| `scan` | Dry run (expired; `--all` = everything) | `ebb scan` |
| `summary` | Fetch a summary of the newest 50 inbox messages | `ebb summary you@gmail.com` |
| `run` | Delete expired mail on enabled accounts | `ebb run` |
| `purge` | Delete everything; requires the confirm flag | `ebb purge you@icloud.com --yes-delete-everything` |
| `set` | Edit the cleanup rule | `ebb set you@gmail.com --disposable-age 1h --max-age 3d --codes on --bulk off --keep-important on` |
| `groq-key` | Set or unset the Groq API key (from stdin) | `pbpaste \| ebb groq-key` |
| `lang` | Show or set language (`pt`, `en`, `system`) | `ebb lang pt` |
| `version` | Print the version | `ebb version` |

TTY `add` prompts for the app password without echo. Other forms:

```bash
ebb add gmail you@gmail.com
ebb add custom you@example.com --host imap.example.com
ebb set you@icloud.com --max-age 7d --disposable-age 2h --keep-flagged on --enabled on --exclude "Receipts"
ebb set you@gmail.com --codes off --bulk on --keep-important on
pbpaste | ebb groq-key
```

`--max-age` and `--disposable-age` accept `30m`, `1h`, `2h`, `12h`, `1d` through
`30d`. `--keep-flagged`, `--keep-important`, `--codes`, `--bulk`, `--permanent`,
and `--enabled` take `on` or `off`. `--exclude` / `--include` take a raw IMAP
mailbox name.

## Uninstall

```bash
brew uninstall --cask ebb
```

To also remove leftover data (`~/Library/Application Support/Ebb`):

```bash
brew uninstall --zap --cask ebb
```

## License

MIT. See [LICENSE](LICENSE).
