# Portal

**Captive portal assistant for [Omarchy](https://omarchy.org/).**

Hotel, café and airport wifi puts a login page between you and the internet.
Windows, macOS and Android all notice and pop that page up for you. Omarchy
doesn't — so the wifi just looks broken.

Portal fixes that. Join the network, get a notification, land on the login page.

---

## Why this is needed

The detection already exists and already works. NetworkManager fetches a known
plain-HTTP URL every time you join a network:

```
/usr/lib/NetworkManager/conf.d/20-connectivity.conf
  uri=http://ping.archlinux.org/nm-check.txt
```

If something answers with a redirect instead of the expected body, NM sets its
connectivity state to `portal` rather than `full`. That is correct, and then
nothing happens with it — `/etc/NetworkManager/dispatcher.d/` is empty and no
part of the desktop listens. The signal is generated and dropped.

It feels worse than it is because of HTTPS. Almost everything you'd try in a
browser is HSTS-protected, so when the portal intercepts it you get a TLS error
(`wrong version number`) rather than a login page. A portal can only redirect
plain HTTP, which is why the manual trick is to visit `http://neverssl.com`.

Portal listens for the state NetworkManager was already reporting, works out the
real login URL, and opens it.

## Install

```bash
omarchy plugin add https://github.com/Yendor86/omarchy-portal.git --enable
```

That is the whole thing. Omarchy clones the repo into
`~/.config/omarchy/plugins/yendor.portal`, validates the manifest, and `--enable`
adds it to `shell.json`. Remove it with `omarchy plugin remove yendor.portal`.

The `omarchy-portal` CLI is inside the plugin at `bin/omarchy-portal`. Put it on
your PATH if you want to run it by hand:

```bash
ln -sfn ~/.config/omarchy/plugins/yendor.portal/bin/omarchy-portal ~/.local/bin/
```

### From a git checkout instead

If you would rather work on it in place:

```bash
git clone https://github.com/Yendor86/omarchy-portal.git ~/code/omarchy-portal
~/code/omarchy-portal/install.sh
```

No sudo. The installer:

1. symlinks the plugin into `~/.config/omarchy/plugins/yendor.portal`
2. puts `omarchy-portal` on your PATH at `~/.local/bin`
3. adds `{"id": "yendor.portal"}` to the `plugins` array in `~/.config/omarchy/shell.json`

Step 3 matters and is easy to miss. A user plugin that is not listed in
`shell.json` is inert — `PluginRegistry.isEnabled()` returns false for anything
that is not first-party and not listed, and `_syncServices()` skips it. The
shell still logs `Local plugin changed, reloading`, reports no error, and simply
never instantiates the service. Your shell.json is backed up to `shell.json.bak`
first.

Plugins reload on save — **but not through a symlink**. Because the installer
symlinks `~/.config/omarchy/plugins/yendor.portal` to wherever you cloned this,
the shell's inotify watch does not see edits to the real files. After a
`git pull` (or any edit), run:

```bash
omarchy-shell shell rescanPlugins
```

You can tell it worked because the `nmcli monitor` process gets a new pid.
This bit us during development: the service kept running old code while
reporting that the plugin had reloaded.

## Use

Nothing, normally — that's the point. It watches and acts on its own.

When you want to drive it by hand:

```bash
omarchy-portal status   # connectivity state, VPN interference, and the portal URL
omarchy-portal signin   # the whole dance: drop the VPN, open the login page
omarchy-portal vpn-up   # put the VPN back after you have signed in
omarchy-portal open     # open the login page now
omarchy-portal url      # just print the URL
```

`signin` exists because doing it by hand is four steps in an order that is easy
to get wrong at 11pm in a hotel. It records what it is about to take down *before* dropping anything, so an
interrupted run still leaves a trail, and `vpn-up` restores exactly those.
If a connection fails to come back, `vpn-up` says so loudly and keeps it on
file — it will never tell you the VPN is up when it is not.

## How it works

- `Portal.qml` is an Omarchy shell service. It runs `nmcli monitor`, which emits
  one line whenever connectivity changes, so there is **no polling** — the process
  sits idle until NetworkManager has something to say.
- On `portal`, it calls `omarchy-portal open`.
- A 90-second cooldown stops the browser reopening while you're still typing your
  room number into the login form.
- It also probes once at startup, because restarting the shell is exactly the sort
  of thing you do while stuck behind a login page.

Detection handles the three shapes portals actually take:

| What the portal does | How it's detected |
|---|---|
| Redirects the check URL (30x) | `Location` header is the login page |
| Answers 200 with its own page | Body isn't NetworkManager's expected text |
| Interferes with the connection | Probes `http://neverssl.com`, and only acts if that actually redirects |

## VPNs and kill switches

This is the case that actually bites, and it is worse than a plain portal.

A VPN kill switch takes the default route so that nothing can leak outside the
tunnel:

```
default via 100.85.0.1  dev pvpnksintrf0  metric 98    <- kill switch
default via 10.107.221.65 dev wlp1s0      metric 600   <- the wifi itself
```

On hotel wifi that produces a deadlock. The tunnel cannot come up until you have
signed in, and the kill switch blocks the sign-in page precisely because it is
doing its job. NetworkManager reports `limited` or `none` rather than `portal`,
because nothing answered at all — it has no way to know a login page exists.

Portal handles this:

- the watcher reacts to `limited` and `none` as well as `portal`, since those are
  the states you actually hit here — but waits ~7s and re-reads the state first,
  because short `limited` blips are common on healthy networks;
- when a VPN or kill switch holds the default route, it does **not** open a
  browser at a page that cannot load. It tells you to drop the VPN first;
- `signin` takes down the VPN **and** its kill switch, including Proton's,
  which is a `dummy` device that a naive type filter misses. It will **not**
  take down your wifi: an earlier version added whatever owned the default
  route unconditionally, which meant disconnecting the very network you were
  trying to sign in to, and then reporting it as a reconnected VPN;
- with no network attached at all, it stays quiet.

The order that works: **disconnect the VPN → join the wifi → sign in → reconnect.**

## What it will not do

- **Only `http` and `https` URLs are opened.** A captive portal chooses the
  redirect target, and `xdg-open` dispatches by scheme — `file://`, `ssh://`,
  `obsidian://` and every other registered handler on the machine. A browser
  prompts before launching those; an automatic tool must not. Loopback
  addresses are refused too.

## What this cannot protect you from

Portal validates the URL a captive portal hands it, and refuses anything that
is not plain `http(s)` pointing somewhere other than your own machine. Three
things are worth being straight about, because no amount of URL validation
fixes them:

- **The attacker owns DNS.** A hostile network can point an ordinary-looking
  hostname at `127.0.0.1`. The address checks catch literals, not resolution,
  and no browser refuses top-level navigation to a host that resolves locally.
- **Opening a page sends your cookies.** A forced top-level navigation carries
  `SameSite=Lax` cookies to whatever host the portal names. That is true of any
  captive-portal helper that uses your normal browser.
- **It opens your normal browser.** macOS, iOS and Android use a dedicated,
  isolated captive-portal browser for exactly these reasons. `xdg-open` has no
  way to express "open this in a throwaway private window", so Portal cannot
  do the same.

If that matters to you, sign in by hand: `omarchy-portal url` prints the login
URL without opening it, and you can paste it into a private window yourself.

## Requirements

Omarchy with `omarchy-shell`, NetworkManager, `curl`, `xdg-open`,
`notify-send`, and `python3`. All of these are present on a stock Omarchy
install — `python3` arrives with `uwsm`, which Omarchy uses to start the
Hyprland session.

`python3` is used for one thing only: deciding whether a URL handed to us by
the network is safe to open. Host parsing and IP classification are far too
easy to get wrong in shell — the previous shell implementation truncated
bracketed IPv6 at the first colon and let every loopback form through — so
that check uses `urllib.parse` and `ipaddress`, which canonicalise IPv6,
IPv4-mapped addresses, and the legacy integer/octal/hex spellings browsers
still honour. If `python3` is missing, Portal refuses to open anything rather
than falling back to a weaker check: it fails closed.

## Licence

MIT. See [LICENSE](LICENSE).
