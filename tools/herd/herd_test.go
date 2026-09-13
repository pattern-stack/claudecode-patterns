package main

import (
	"strings"
	"testing"
)

const sampleInventory = `@@sessions
{"sessions":[{"default":true,"name":"default","running":true},{"default":false,"name":"review","running":false},{"default":false,"name":"agents","running":true}]}
@@workspaces default
{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[{"agent_status":"working"},{"agent_status":"done"}]}}
@@workspaces agents
{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[{"agent_status":"blocked"},{"agent_status":"blocked"},{"agent_status":"idle"}]}}
`

func TestParseInventory(t *testing.T) {
	sessions, workspaces, ok := parseInventory(sampleInventory)
	if !ok {
		t.Fatal("expected herdr to be present")
	}
	if len(sessions) != 3 || sessions[1].Name != "review" || sessions[1].Running {
		t.Fatalf("sessions = %+v", sessions)
	}
	for name, want := range map[string]string{"default": "1 done", "agents": "2 blocked", "review": ""} {
		if got := agentSummary(workspaces[name]); got != want {
			t.Errorf("agentSummary(%s) = %q, want %q", name, got, want)
		}
	}
	if _, _, ok := parseInventory("@@noherdr\n"); ok {
		t.Error("expected ok=false when herdr is missing")
	}
}

func TestResolveRef(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	hosts := []Host{{Name: localHost}, {Name: "homelab", Target: "claude@10.0.0.2"}}
	for _, c := range []struct{ ref, want, target string }{
		{"agents", "local/agents", ""},
		{"homelab/review", "homelab/review", "claude@10.0.0.2"},
		{"homelab/", "homelab/default", "claude@10.0.0.2"},
	} {
		s, err := resolveRef(c.ref, hosts)
		if err != nil {
			t.Fatalf("%s: %v", c.ref, err)
		}
		if s.Ref() != c.want || s.Target != c.target {
			t.Errorf("%s → %s @ %q, want %s @ %q", c.ref, s.Ref(), s.Target, c.want, c.target)
		}
	}
	for _, bad := range []string{"nohost/x", "homelab/bad name", "hub/missing"} {
		if _, err := resolveRef(bad, hosts); err == nil {
			t.Errorf("%s: expected an error", bad)
		}
	}
}

func TestAttachCmd(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", "/state")
	for _, c := range []struct {
		s        Session
		args     string
		hubState bool
	}{
		{Session{Kind: "session", Host: localHost, Name: defaultSession}, "herdr", false},
		{Session{Kind: "session", Host: localHost, Name: "agents"}, "herdr --session agents", false},
		{Session{Kind: "session", Host: "homelab", Target: "homelab", Name: defaultSession}, "herdr --remote homelab", false},
		{Session{Kind: "session", Host: "homelab", Target: "homelab", Name: "review"}, "herdr --remote homelab --session review", false},
		{Session{Kind: hubHost, Host: hubHost, Name: "overview"}, "herdr --session overview", true},
	} {
		cmd := attachCmd(c.s)
		if got := strings.Join(cmd.Args, " "); got != c.args {
			t.Errorf("%s: args = %q, want %q", c.s.Ref(), got, c.args)
		}
		hubState := strings.Contains(strings.Join(cmd.Env, "\n"), "XDG_STATE_HOME=/state/herd/hubs/overview")
		if hubState != c.hubState {
			t.Errorf("%s: hub XDG_STATE_HOME set = %v, want %v", c.s.Ref(), hubState, c.hubState)
		}
	}
}

func TestBuildRows(t *testing.T) {
	hosts := []Host{{Name: localHost}, {Name: "homelab", Target: "homelab"}, {Name: "laptop", Target: "laptop"}}
	inv := Inventory{
		Sessions: []Session{
			{Host: "homelab", Name: "default", Running: true},
			{Host: localHost, Name: "default", Running: true},
			{Kind: hubHost, Host: hubHost, Name: "overview"},
		},
		Offline: []Offline{{Host: "laptop", Error: "timed out"}},
	}
	outline := func(rows []listRow) string {
		var parts []string
		for _, r := range rows {
			switch r.kind {
			case rowHeading:
				parts = append(parts, "#"+r.title)
			case rowSession:
				parts = append(parts, r.session.Ref())
			case rowOffline:
				parts = append(parts, "!"+r.title)
			}
		}
		return strings.Join(parts, " ")
	}
	if got, want := outline(buildRows(inv, hosts, "")), "#local local/default #homelab homelab/default #hubs hub/overview #offline !laptop"; got != want {
		t.Errorf("rows = %q, want %q", got, want)
	}
	if got, want := outline(buildRows(inv, hosts, "HOME")), "#homelab homelab/default"; got != want {
		t.Errorf("filtered rows = %q, want %q", got, want)
	}
}
