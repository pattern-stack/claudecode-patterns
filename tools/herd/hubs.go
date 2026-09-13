package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

func hubsDir() string { return filepath.Join(xdgDir("XDG_STATE_HOME", ".local/state"), "herd", "hubs") }

func hubDir(name string) string { return filepath.Join(hubsDir(), name) }

// loadHubs maps each hub to its member labels, read from the hub's private herdr state.
func loadHubs() map[string][]string {
	hubs := map[string][]string{}
	entries, err := os.ReadDir(hubsDir())
	if err != nil {
		return hubs
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		members := []string{}
		var endpoints struct {
			SSH []struct {
				Label  string `json:"label"`
				Target string `json:"target"`
			} `json:"ssh"`
		}
		data, err := os.ReadFile(filepath.Join(hubDir(e.Name()), "herdr", "client", "endpoints.json"))
		if err == nil && json.Unmarshal(data, &endpoints) == nil {
			for _, m := range endpoints.SSH {
				if m.Label != "" {
					members = append(members, m.Label)
				} else {
					members = append(members, m.Target)
				}
			}
		}
		hubs[e.Name()] = members
	}
	return hubs
}

// createHub starts a local session for the hub and saves its members in the hub's private state.
func createHub(name string, refs []string, hosts []Host) error {
	if !nameRE.MatchString(name) || name == defaultSession {
		return fmt.Errorf("invalid hub name %q", name)
	}
	if _, exists := loadHubs()[name]; exists {
		return fmt.Errorf("hub/%s already exists — use `herd hub add %s HOST/SESSION...`", name, name)
	}
	if exists, _ := sessionState("", name); exists {
		return fmt.Errorf("there's already a local session named %q; pick another hub name", name)
	}
	if err := os.MkdirAll(hubDir(name), 0o755); err != nil {
		return err
	}
	if _, err := ensureRunning("", name); err != nil {
		return err
	}
	return addHubMembers(name, refs, hosts)
}

// addHubMembers saves each HOST/SESSION as a machine in the hub's private herdr state.
func addHubMembers(hub string, refs []string, hosts []Host) error {
	for _, ref := range refs {
		s, err := resolveRef(ref, hosts)
		if err != nil {
			return err
		}
		if s.IsHub() {
			return errors.New("a hub can't contain another hub")
		}
		target := s.Target
		if target == "" {
			// herdr reaches every machine over SSH, including this one.
			target = "localhost"
			warn("%s is reached over `ssh localhost`, so this machine needs an SSH server", s.Ref())
		}
		step("adding %s to hub/%s", s.Ref(), hub)
		cmd := exec.Command("herdr", "machine", "add", target, "--label", s.Ref(), "--remote-session", s.Name)
		cmd.Env = append(os.Environ(), "XDG_STATE_HOME="+hubDir(hub))
		cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("herdr machine add %s: %w", s.Ref(), err)
		}
	}
	return nil
}

// removeHub deletes the hub's own session and its private state; member sessions are untouched.
func removeHub(name string) error {
	_, _ = sessionCommand("", "stop", name)
	_, _ = sessionCommand("", "delete", name)
	return os.RemoveAll(hubDir(name))
}
