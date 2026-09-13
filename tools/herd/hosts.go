package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

const (
	localHost      = "local"
	hubHost        = "hub"
	defaultSession = "default"
)

var nameRE = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`)

// Host is a machine herd can reach. Target is its ssh target; empty means this machine.
type Host struct {
	Name   string
	Target string
}

func xdgDir(env, fallback string) string {
	if v := os.Getenv(env); v != "" {
		return v
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, fallback)
}

func hostsFile() string {
	return filepath.Join(xdgDir("XDG_CONFIG_HOME", ".config"), "herd", "hosts")
}

// loadHosts reads ~/.config/herd/hosts (`<name> [ssh-target]` per line). This machine is always first.
func loadHosts() []Host {
	hosts := []Host{{Name: localHost}}
	f, err := os.Open(hostsFile())
	if err != nil {
		return hosts
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line, _, _ := strings.Cut(scanner.Text(), "#")
		fields := strings.Fields(line)
		if len(fields) == 0 || fields[0] == localHost || fields[0] == hubHost {
			continue
		}
		h := Host{Name: fields[0], Target: fields[0]}
		if len(fields) > 1 {
			h.Target = fields[1]
		}
		hosts = append(hosts, h)
	}
	return hosts
}

func writeHosts(hosts []Host) error {
	path := hostsFile()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	var b strings.Builder
	b.WriteString("# herd hosts: <name> [ssh-target]   (target defaults to the name, e.g. an ~/.ssh/config alias)\n")
	for _, h := range hosts {
		switch {
		case h.Name == localHost:
		case h.Target == h.Name:
			fmt.Fprintln(&b, h.Name)
		default:
			fmt.Fprintf(&b, "%s %s\n", h.Name, h.Target)
		}
	}
	return os.WriteFile(path, []byte(b.String()), 0o644)
}

func findHost(hosts []Host, name string) (Host, bool) {
	for _, h := range hosts {
		if h.Name == name {
			return h, true
		}
	}
	return Host{}, false
}
