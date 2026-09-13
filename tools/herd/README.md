# herd

Find, create and attach [herdr](https://herdr.dev) sessions across your machines. It's a single Go binary with a [Bubble Tea](https://github.com/charmbracelet/bubbletea) picker, styled with the tui-patterns palette.

```
 herd  2 hosts · 4 sessions
 ────────────────────────────────────────────
  local  this machine
  ›  ● default       1 ws     1 working

  homelab
     ● default       2 ws     2 done
     ○ review        stopped

  hubs
     ● overview      0 ws     2 members
 ────────────────────────────────────────────
 ↵ attach  n new  s stop  d delete  / filter  r refresh  q quit
```

## How herdr sessions work

- **Session**: one herdr server on one machine, with its own workspaces, tabs, panes and agents.
  - It's isolated from every other session and keeps running after you detach.
  - A machine can have many (`herdr --session NAME`).
- **Client**: the TUI you look through. It attaches to exactly one session:
  - `herdr --session NAME` on this machine;
  - `herdr --remote HOST --session NAME` over SSH.

  Several clients on different devices can attach to the same session at once.
- **Saved machines**: a list in the client that adds other sessions to its sidebar (`herdr machine add`).
  - It lives in the client's herdr state dir (`$XDG_STATE_HOME/herdr/client/`), so by default every herdr window on the device shows it.
  - Indexed keys like `switch_workspace` act on whichever machine is selected in the sidebar.

herd is a thin layer over those: a host list, SSH, and a private state dir for each hub.

## Install

```sh
just herd::install            # build into ~/.local/bin/herd (needs Go 1.25+)
just herd::deploy homelab     # cross-compile for that machine and copy it over
just herd::check              # go vet + go test
```

Target machines don't need Go. `deploy` asks the host for `uname -sm`, builds a static binary for its OS and CPU, and copies it into `~/.local/bin`.

Every machine needs herdr, and must accept non-interactive SSH from the device you run herd on: `ssh -o BatchMode=yes HOST true` has to succeed. herdr's own remote connections need the same. On macOS, turn on System Settings → General → Sharing → Remote Login.

## Use

```sh
herd                          # the picker
herd ls [--json]              # every session on every host
herd hosts add homelab        # an ~/.ssh/config alias (or: herd hosts add NAME user@host)
herd new homelab agents       # start a headless session (-a to attach)
herd attach homelab/agents    # attach to exactly that session
herd stop homelab/agents
herd rm homelab/agents        # stop and delete (asks first; -y skips)
```

References look like `HOST/SESSION`:
- `HOST/` means that host's default session.
- A bare name means a session on this machine.
- `hub/NAME` means a hub.

### Picker keys

| Key | Action |
|---|---|
| `↵` | Attach. herd hands the terminal to herdr; detach with prefix+q to come back. |
| `n` | New session: pick a host, name it, and it starts headless, then attaches. |
| `s` / `d` | Stop / delete the selected session (delete asks first). |
| `/` | Filter by `host/session`. |
| `r` | Refresh. |
| `q` / `esc` | Quit. |

The theme follows your terminal's background. Set `HERD_THEME=light` or `HERD_THEME=dark` to force one.

## Hubs

A hub is a local session whose sidebar also shows chosen sessions. Those sessions don't appear in any of your other herdr windows.

```sh
herd hub new overview homelab/agents homelab/review
herd attach hub/overview
herd hub add overview laptop/default
herd hub rm overview
```

How it works:
- The hub's saved machines live in `~/.local/state/herd/hubs/<name>/`, and herd attaches with `XDG_STATE_HOME` pointed there.
- herd starts the hub's server first with your normal environment, so its panes don't inherit that directory.
- Members on the hub's own machine are reached over `ssh localhost`, so that machine needs an SSH server as well.

## iTerm2

To open windows at the picker, set a profile's command to `/bin/zsh -lc 'exec herd'`. The profile needs the same key mappings as your herdr profile.

## Sandboxes

A deploy can start a session headless with `herdr --session <workspace> server`, then register its host with `herd hosts add`. `herd ls --json` gives other tooling the full inventory.
