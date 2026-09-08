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

Plugins reload on save; if it doesn't pick up, `omarchy-shell shell rescanPlugins`.

## Use

Nothing, normally — that's the point. It watches and acts on its own.

When you want to drive it by hand:

```bash
omarchy-portal status   # connectivity state, and the portal URL if there is one
omarchy-portal open     # open the login page now
omarchy-portal url      # just print the URL
```

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
| Interferes with the connection | Falls back to `http://neverssl.com` |

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
  the states you actually hit here;
- when a VPN or kill switch holds the default route, it does **not** open a
  browser at a page that cannot load. It tells you to drop the VPN first;
- with no network attached at all, it stays quiet.

The order that works: **disconnect the VPN → join the wifi → sign in → reconnect.**

## Requirements

Omarchy with `omarchy-shell`, NetworkManager, `curl`, `xdg-open`, and
`notify-send`. All of these are already on a stock Omarchy install.

## Licence

MIT. See [LICENSE](LICENSE).
