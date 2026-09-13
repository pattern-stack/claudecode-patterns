package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"os"
	"os/exec"
	"slices"
	"strings"
	"sync"
	"time"
)

// inventorySh prints a host's sessions, then the workspaces of each running one.
const inventorySh = shPath + `
command -v herdr >/dev/null 2>&1 || { echo "@@noherdr"; exit 0; }
echo "@@sessions"
herdr session list --json
for s in $(herdr session list | awk 'NR > 1 && $2 == "running" { print $1 }'); do
  echo "@@workspaces $s"
  if [ "$s" = default ]; then herdr workspace list; else herdr --session "$s" workspace list; fi
done
`

// startSh starts a headless session server ($1), detached from this shell.
const startSh = shPath + `
if [ "$1" = default ]; then set -- herdr server; else set -- herdr --session "$1" server; fi
if command -v setsid >/dev/null 2>&1; then
  setsid -f "$@" >/dev/null 2>&1 </dev/null
else
  nohup "$@" >/dev/null 2>&1 </dev/null &
fi
`

const sessionSh = shPath + `herdr session "$@"` + "\n"

var errNested = errors.New("you're inside a herdr pane, and herdr can't nest — detach (prefix+q) or use a plain terminal")

type herdrSession struct {
	Name    string `json:"name"`
	Running bool   `json:"running"`
}

type herdrWorkspace struct {
	AgentStatus string `json:"agent_status"`
}

// Session is one herdr session on one host, or a hub: a local session with its own sidebar.
type Session struct {
	Kind       string   `json:"kind"` // "session" or "hub"
	Host       string   `json:"host"`
	Target     string   `json:"target,omitempty"`
	Name       string   `json:"session"`
	Running    bool     `json:"running"`
	Workspaces int      `json:"workspaces"`
	Agents     string   `json:"agents,omitempty"` // most urgent agent state, e.g. "2 blocked"
	Members    []string `json:"members,omitempty"`
}

func (s Session) Ref() string { return s.Host + "/" + s.Name }
func (s Session) IsHub() bool { return s.Kind == hubHost }

type Offline struct {
	Host  string `json:"host"`
	Error string `json:"error"`
}

type Inventory struct {
	Sessions []Session `json:"sessions"`
	Offline  []Offline `json:"offline"`
}

// parseInventory reads inventorySh output. ok is false when the host has no herdr.
func parseInventory(out string) (sessions []herdrSession, workspaces map[string][]herdrWorkspace, ok bool) {
	workspaces = map[string][]herdrWorkspace{}
	section, current := "", ""
	for _, line := range strings.Split(out, "\n") {
		if strings.HasPrefix(line, "@@noherdr") {
			return nil, nil, false
		}
		if rest, found := strings.CutPrefix(line, "@@"); found {
			section, current, _ = strings.Cut(strings.TrimSpace(rest), " ")
			continue
		}
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "{") {
			continue
		}
		switch section {
		case "sessions":
			var data struct {
				Sessions []herdrSession `json:"sessions"`
			}
			if json.Unmarshal([]byte(line), &data) == nil {
				sessions = data.Sessions
			}
		case "workspaces":
			var data struct {
				Result struct {
					Workspaces []herdrWorkspace `json:"workspaces"`
				} `json:"result"`
			}
			if json.Unmarshal([]byte(line), &data) == nil {
				workspaces[current] = data.Result.Workspaces
			}
		}
	}
	return sessions, workspaces, true
}

// agentSummary is the most urgent agent state across a session's workspaces, e.g. "2 blocked".
func agentSummary(workspaces []herdrWorkspace) string {
	for _, state := range []string{"blocked", "done", "working", "idle"} {
		n := 0
		for _, w := range workspaces {
			if w.AgentStatus == state {
				n++
			}
		}
		if n > 0 {
			return fmt.Sprintf("%d %s", n, state)
		}
	}
	return ""
}

// loadInventory asks every host for its sessions, in parallel.
func loadInventory(hosts []Host) Inventory {
	type result struct {
		sessions   []herdrSession
		workspaces map[string][]herdrWorkspace
		err        string
	}
	results := make([]result, len(hosts))
	var wg sync.WaitGroup
	for i, h := range hosts {
		wg.Add(1)
		go func() {
			defer wg.Done()
			out, err := runOn(h.Target, inventorySh)
			if err != nil {
				results[i].err = err.Error()
				return
			}
			sessions, workspaces, ok := parseInventory(out)
			if !ok {
				results[i].err = "herdr not installed"
				return
			}
			results[i] = result{sessions: sessions, workspaces: workspaces}
		}()
	}
	wg.Wait()

	hubs := loadHubs()
	listed := map[string]bool{}
	inv := Inventory{Sessions: []Session{}, Offline: []Offline{}}
	for i, h := range hosts {
		r := results[i]
		if r.err != "" {
			inv.Offline = append(inv.Offline, Offline{Host: h.Name, Error: r.err})
			continue
		}
		for _, hs := range r.sessions {
			s := Session{Kind: "session", Host: h.Name, Target: h.Target, Name: hs.Name, Running: hs.Running}
			if hs.Running {
				s.Workspaces = len(r.workspaces[hs.Name])
				s.Agents = agentSummary(r.workspaces[hs.Name])
			}
			if members, isHub := hubs[hs.Name]; isHub && h.Name == localHost {
				s.Kind, s.Host, s.Members = hubHost, hubHost, members
				listed[hs.Name] = true
			}
			inv.Sessions = append(inv.Sessions, s)
		}
	}
	for _, name := range slices.Sorted(maps.Keys(hubs)) {
		if !listed[name] {
			inv.Sessions = append(inv.Sessions, Session{Kind: hubHost, Host: hubHost, Name: name, Members: hubs[name]})
		}
	}
	return inv
}

// resolveRef turns HOST/SESSION, HOST/ (its default session), hub/NAME or a bare
// local session name into a Session.
func resolveRef(ref string, hosts []Host) (Session, error) {
	host, name, found := strings.Cut(ref, "/")
	if !found {
		host, name = localHost, ref
	}
	if name == "" {
		name = defaultSession
	}
	if !nameRE.MatchString(name) {
		return Session{}, fmt.Errorf("invalid session name %q (letters, digits, - and _)", name)
	}
	if host == hubHost {
		if _, ok := loadHubs()[name]; !ok {
			return Session{}, fmt.Errorf("no hub named %q — see `herd hub ls`", name)
		}
		return Session{Kind: hubHost, Host: hubHost, Name: name}, nil
	}
	h, ok := findHost(hosts, host)
	if !ok {
		return Session{}, fmt.Errorf("unknown host %q — add it with `herd hosts add %s [ssh-target]`", host, host)
	}
	return Session{Kind: "session", Host: h.Name, Target: h.Target, Name: name}, nil
}

func listSessions(target string) []herdrSession {
	out, err := runOn(target, sessionSh, "list", "--json")
	if err != nil {
		return nil
	}
	var data struct {
		Sessions []herdrSession `json:"sessions"`
	}
	_ = json.Unmarshal([]byte(out), &data)
	return data.Sessions
}

func sessionState(target, name string) (exists, running bool) {
	for _, s := range listSessions(target) {
		if s.Name == name {
			return true, s.Running
		}
	}
	return false, false
}

// ensureRunning starts a headless session unless it's already up; started reports whether it had to.
func ensureRunning(target, name string) (started bool, err error) {
	if _, running := sessionState(target, name); running {
		return false, nil
	}
	if _, err := runOn(target, startSh, name); err != nil {
		return false, fmt.Errorf("couldn't start %s: %w", name, err)
	}
	for deadline := time.Now().Add(10 * time.Second); time.Now().Before(deadline); time.Sleep(500 * time.Millisecond) {
		if _, running := sessionState(target, name); running {
			return true, nil
		}
	}
	return false, fmt.Errorf("started %s, but it still isn't running after 10s", name)
}

func sessionCommand(target, verb, name string) (string, error) {
	out, err := runOn(target, sessionSh, verb, name)
	return strings.TrimSpace(out), err
}

// deleteSession stops and deletes a session, or removes a hub. Default sessions are refused.
func deleteSession(s Session) error {
	if s.IsHub() {
		return removeHub(s.Name)
	}
	if s.Name == defaultSession {
		return errors.New("won't delete a default session — stop it instead")
	}
	_, _ = sessionCommand(s.Target, "stop", s.Name)
	_, err := sessionCommand(s.Target, "delete", s.Name)
	return err
}

// attachCmd is the herdr client command for exactly this session.
func attachCmd(s Session) *exec.Cmd {
	var args []string
	if s.Target != "" {
		args = append(args, "--remote", s.Target)
	}
	if s.Name != defaultSession {
		args = append(args, "--session", s.Name)
	}
	cmd := exec.Command("herdr", args...)
	cmd.Env = os.Environ()
	if s.IsHub() {
		cmd.Env = append(cmd.Env, "XDG_STATE_HOME="+hubDir(s.Name))
	}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd
}

// prepareAttach refuses to nest inside herdr, and starts a hub's server with the normal
// environment first, so its panes don't inherit the hub's private XDG_STATE_HOME.
func prepareAttach(s Session) error {
	if os.Getenv("HERDR_ENV") == "1" {
		return errNested
	}
	if s.IsHub() {
		_, err := ensureRunning("", s.Name)
		return err
	}
	return nil
}
