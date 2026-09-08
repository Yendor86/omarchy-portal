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

No sudo. It symlinks the plugin into `~/.config/omarchy/plugins/yendor.portal`
and puts `omarchy-portal` on your PATH. Plugins reload on save; if it doesn't
pick up, `omarchy-shell shell rescanPlugins`.

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

## Requirements

Omarchy with `omarchy-shell`, NetworkManager, `curl`, `xdg-open`, and
`notify-send`. All of these are already on a stock Omarchy install.

## Licence

MIT. See [LICENSE](LICENSE).
