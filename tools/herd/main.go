// herd finds, creates and attaches herdr sessions across your machines.
//
// A herdr session is one isolated server on one machine. herd keeps a short host
// list (~/.config/herd/hosts), asks every host for its sessions over SSH, and
// attaches you to exactly one of them. A hub is a local session whose sidebar also
// shows chosen sessions, kept in its own herdr state dir (~/.local/state/herd/hubs).
package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"os"
	"slices"
	"strings"
	"syscall"

	"charm.land/lipgloss/v2"
	tea "charm.land/bubbletea/v2"
)

var version = "0.2.0"

func main() {
	initTheme()
	if err := run(os.Args[1:]); err != nil {
		fail(err)
		os.Exit(1)
	}
}

func usage(s string) error { return fmt.Errorf("usage: herd %s", s) }

// splitFlags pulls known boolean flags out of args, wherever they appear.
func splitFlags(args []string, names ...string) ([]string, map[string]bool) {
	var positional []string
	set := map[string]bool{}
	for _, a := range args {
		if slices.Contains(names, a) {
			set[a] = true
		} else {
			positional = append(positional, a)
		}
	}
	return positional, set
}

func run(args []string) error {
	if len(args) == 0 {
		return runPicker()
	}
	hosts := loadHosts()
	cmd, rest := args[0], args[1:]
	switch cmd {
	case "help", "-h", "--help":
		printHelp()
		return nil
	case "version", "--version":
		fmt.Println("herd " + version)
		return nil
	case "ls":
		_, flags := splitFlags(rest, "--json")
		inv := loadInventory(hosts)
		if flags["--json"] {
			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(inv)
		}
		printInventory(inv, hosts)
		return nil
	case "attach":
		if len(rest) != 1 {
			return usage("attach REF")
		}
		s, err := resolveRef(rest[0], hosts)
		if err != nil {
			return err
		}
		return execAttach(s)
	case "new":
		return runNew(rest, hosts)
	case "stop":
		if len(rest) != 1 {
			return usage("stop REF")
		}
		s, err := resolveRef(rest[0], hosts)
		if err != nil {
			return err
		}
		switch exists, running := sessionState(s.Target, s.Name); {
		case !exists:
			return fmt.Errorf("no session %s", s.Ref())
		case !running:
			hint("%s isn't running", s.Ref())
			return nil
		}
		if _, err := sessionCommand(s.Target, "stop", s.Name); err != nil {
			return err
		}
		success("stopped %s", s.Ref())
		return nil
	case "rm":
		pos, flags := splitFlags(rest, "-y", "--yes")
		if len(pos) != 1 {
			return usage("rm REF [-y]")
		}
		s, err := resolveRef(pos[0], hosts)
		if err != nil {
			return err
		}
		if s.IsHub() {
			return errors.New("use `herd hub rm NAME` for hubs")
		}
		if s.Name == defaultSession {
			return errors.New("won't delete a default session — stop it instead")
		}
		if exists, _ := sessionState(s.Target, s.Name); !exists {
			return fmt.Errorf("no session %s", s.Ref())
		}
		if ok, err := confirm("delete "+s.Ref()+"? Its panes and agents are killed.", flags["-y"] || flags["--yes"]); !ok {
			return err
		}
		if err := deleteSession(s); err != nil {
			return err
		}
		success("deleted %s", s.Ref())
		return nil
	case "hosts":
		return runHosts(rest, hosts)
	case "hub":
		return runHub(rest, hosts)
	}
	return fmt.Errorf("unknown command %q — see `herd help`", cmd)
}

func runPicker() error {
	if os.Getenv("HERDR_ENV") == "1" {
		return errNested
	}
	hosts := loadHosts()
	if !isTerminal(os.Stdin) || !isTerminal(os.Stdout) {
		printInventory(loadInventory(hosts), hosts)
		return nil
	}
	_, err := tea.NewProgram(newPicker(hosts)).Run()
	return err
}

func runNew(args []string, hosts []Host) error {
	pos, flags := splitFlags(args, "-a", "--attach")
	var ref string
	switch len(pos) {
	case 1:
		if _, isHost := findHost(hosts, pos[0]); isHost {
			return fmt.Errorf("%q is a host — did you mean `herd new %s NAME`? (`herd new local %s` names a session here)", pos[0], pos[0], pos[0])
		}
		ref = localHost + "/" + pos[0]
	case 2:
		ref = pos[0] + "/" + pos[1]
	default:
		return usage("new [HOST] NAME [-a]")
	}
	if strings.HasSuffix(ref, "/") {
		return usage("new [HOST] NAME [-a]")
	}
	s, err := resolveRef(ref, hosts)
	if err != nil {
		return err
	}
	started, err := ensureRunning(s.Target, s.Name)
	if err != nil {
		return err
	}
	if started {
		success("started %s", s.Ref())
	} else {
		hint("%s is already running", s.Ref())
	}
	if flags["-a"] || flags["--attach"] {
		return execAttach(s)
	}
	hint("  attach with `herd attach %s`", s.Ref())
	return nil
}

// execAttach replaces herd with the herdr client for this session.
func execAttach(s Session) error {
	if err := prepareAttach(s); err != nil {
		return err
	}
	cmd := attachCmd(s)
	if cmd.Err != nil {
		return cmd.Err
	}
	return syscall.Exec(cmd.Path, cmd.Args, cmd.Env)
}

func confirm(prompt string, yes bool) (bool, error) {
	if yes {
		return true, nil
	}
	if !isTerminal(os.Stdin) {
		return false, errors.New("refusing without --yes (not a terminal)")
	}
	lipgloss.Print(st.Warning.Render(glyphWarning) + " " + prompt + " " + st.Dim.Render("[y/N] "))
	answer, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	answer = strings.ToLower(strings.TrimSpace(answer))
	if answer == "y" || answer == "yes" {
		return true, nil
	}
	hint("kept it")
	return false, nil
}

func runHosts(args []string, hosts []Host) error {
	if len(args) == 0 || args[0] == "ls" {
		lipgloss.Println("")
		for _, h := range hosts {
			target := h.Target
			if h.Name == localHost {
				target = "this machine"
			}
			lipgloss.Println("  " + st.Heading.Render(pad(h.Name, 14)) + st.Dim.Render(target))
		}
		hint("\n  %s\n", hostsFile())
		return nil
	}
	switch args[0] {
	case "add":
		if len(args) < 2 || len(args) > 3 {
			return usage("hosts add NAME [TARGET]")
		}
		name, target := args[1], args[1]
		if len(args) == 3 {
			target = args[2]
		}
		if !nameRE.MatchString(name) || name == localHost || name == hubHost {
			return fmt.Errorf("invalid host name %q", name)
		}
		if i := slices.IndexFunc(hosts, func(h Host) bool { return h.Name == name }); i >= 0 {
			hosts[i].Target = target
		} else {
			hosts = append(hosts, Host{Name: name, Target: target})
		}
		if err := writeHosts(hosts); err != nil {
			return err
		}
		success("%s %s %s", name, glyphArrow, target)
		return nil
	case "rm":
		if len(args) != 2 {
			return usage("hosts rm NAME")
		}
		kept := slices.DeleteFunc(slices.Clone(hosts), func(h Host) bool { return h.Name == args[1] && h.Name != localHost })
		if len(kept) == len(hosts) {
			return fmt.Errorf("no host named %q", args[1])
		}
		if err := writeHosts(kept); err != nil {
			return err
		}
		success("removed %s", args[1])
		return nil
	}
	return usage("hosts [ls | add NAME [TARGET] | rm NAME]")
}

func runHub(args []string, hosts []Host) error {
	pos, flags := splitFlags(args, "-y", "--yes")
	if len(pos) == 0 || pos[0] == "ls" {
		hubs := loadHubs()
		if len(hubs) == 0 {
			hint("no hubs yet — create one with `herd hub new NAME HOST/SESSION...`")
			return nil
		}
		lipgloss.Println("")
		for _, name := range slices.Sorted(maps.Keys(hubs)) {
			members := strings.Join(hubs[name], ", ")
			if members == "" {
				members = "no members"
			}
			lipgloss.Println("  " + st.Tool.Render(pad("hub/"+name, 20)) + st.Dim.Render(members))
		}
		lipgloss.Println("")
		return nil
	}
	if len(pos) < 2 {
		return usage("hub [ls | new NAME [REF...] | add NAME REF... | rm NAME [-y]]")
	}
	action, name, refs := pos[0], pos[1], pos[2:]
	if action != "new" {
		if _, ok := loadHubs()[name]; !ok {
			return fmt.Errorf("no hub named %q — see `herd hub ls`", name)
		}
	}
	switch action {
	case "new":
		if err := createHub(name, refs, hosts); err != nil {
			return err
		}
		success("hub/%s is ready", name)
		hint("  attach with `herd attach hub/%s`", name)
		return nil
	case "add":
		if len(refs) == 0 {
			return usage("hub add NAME HOST/SESSION...")
		}
		if err := addHubMembers(name, refs, hosts); err != nil {
			return err
		}
		success("added %s to hub/%s", countLabel(len(refs), "member", "members"), name)
		return nil
	case "rm":
		if ok, err := confirm("delete hub/"+name+"? Its own session is deleted; member sessions are untouched.", flags["-y"] || flags["--yes"]); !ok {
			return err
		}
		if err := removeHub(name); err != nil {
			return err
		}
		success("removed hub/%s", name)
		return nil
	}
	return usage("hub [ls | new NAME [REF...] | add NAME REF... | rm NAME [-y]]")
}
