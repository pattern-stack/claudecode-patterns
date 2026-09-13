package main

import (
	"fmt"
	"os"
	"strings"

	"charm.land/lipgloss/v2"
)

func success(format string, a ...any) {
	lipgloss.Println(st.Success.Render(glyphCheck) + " " + fmt.Sprintf(format, a...))
}

func step(format string, a ...any) {
	lipgloss.Println(st.Accent.Render(glyphArrow) + " " + fmt.Sprintf(format, a...))
}

func hint(format string, a ...any) {
	lines := strings.Split(fmt.Sprintf(format, a...), "\n")
	for i, line := range lines {
		lines[i] = st.Dim.Render(line)
	}
	lipgloss.Println(strings.Join(lines, "\n"))
}

func warn(format string, a ...any) {
	lipgloss.Fprintln(os.Stderr, st.Warning.Render(glyphWarning)+" "+fmt.Sprintf(format, a...))
}

func fail(err error) {
	lipgloss.Fprintln(os.Stderr, st.Error.Render(glyphCross+" "+err.Error()))
}

func pad(s string, width int) string {
	return s + strings.Repeat(" ", max(0, width-lipgloss.Width(s)))
}

func countLabel(n int, one, many string) string {
	if n == 1 {
		return "1 " + one
	}
	return fmt.Sprintf("%d %s", n, many)
}

type rowKind int

const (
	rowHeading rowKind = iota
	rowSession
	rowOffline
)

type listRow struct {
	kind    rowKind
	title   string // heading or offline host
	detail  string // heading subtitle or offline error
	session Session
}

// buildRows groups sessions under this machine, each host in the hosts file, hubs,
// and hosts that couldn't be reached. filter keeps sessions whose reference contains it.
func buildRows(inv Inventory, hosts []Host, filter string) []listRow {
	filter = strings.ToLower(filter)
	byHost := map[string][]Session{}
	for _, s := range inv.Sessions {
		byHost[s.Host] = append(byHost[s.Host], s)
	}
	var rows []listRow
	group := func(title, detail string, sessions []Session) {
		var picked []listRow
		for _, s := range sessions {
			if filter == "" || strings.Contains(strings.ToLower(s.Ref()), filter) {
				picked = append(picked, listRow{kind: rowSession, session: s})
			}
		}
		if len(picked) > 0 {
			rows = append(append(rows, listRow{kind: rowHeading, title: title, detail: detail}), picked...)
		}
	}
	for _, h := range hosts {
		detail := ""
		switch {
		case h.Name == localHost:
			detail = "this machine"
		case h.Target != h.Name:
			detail = h.Target
		}
		group(h.Name, detail, byHost[h.Name])
	}
	group("hubs", "", byHost[hubHost])
	if filter == "" && len(inv.Offline) > 0 {
		rows = append(rows, listRow{kind: rowHeading, title: "offline"})
		for _, o := range inv.Offline {
			rows = append(rows, listRow{kind: rowOffline, title: o.Host, detail: o.Error})
		}
	}
	return rows
}

func nameWidth(inv Inventory) int {
	w := 12
	for _, s := range inv.Sessions {
		w = max(w, lipgloss.Width(s.Name))
	}
	for _, o := range inv.Offline {
		w = max(w, lipgloss.Width(o.Host))
	}
	return w
}

func agentStyle(summary string) lipgloss.Style {
	switch {
	case strings.HasSuffix(summary, "blocked"):
		return st.Warning
	case strings.HasSuffix(summary, "done"):
		return st.Success
	case strings.HasSuffix(summary, "working"):
		return st.Running
	}
	return st.Dim
}

func renderRow(r listRow, nameW int, selected bool) string {
	switch r.kind {
	case rowHeading:
		line := "  " + st.Heading.Render(r.title)
		if r.detail != "" {
			line += "  " + st.Dim.Render(r.detail)
		}
		return line
	case rowOffline:
		return "     " + st.Error.Render(glyphCross) + " " + st.Text.Render(pad(r.title, nameW)) + "  " + st.Dim.Render(r.detail)
	}
	s := r.session
	cursor, name := " ", st.Text.Render(pad(s.Name, nameW))
	if selected {
		cursor, name = st.Accent.Render(glyphCursor), st.Accent.Bold(true).Render(pad(s.Name, nameW))
	}
	dot, state := st.Dim.Render(glyphStopped), "stopped"
	if s.Running {
		dot, state = st.Success.Render(glyphRunning), fmt.Sprintf("%d ws", s.Workspaces)
	}
	info := ""
	switch {
	case s.IsHub():
		info = st.Tool.Render(countLabel(len(s.Members), "member", "members"))
	case s.Agents != "":
		info = agentStyle(s.Agents).Render(s.Agents)
	}
	if info != "" {
		state = pad(state, 9)
	}
	return "  " + cursor + "  " + dot + " " + name + "  " + st.Dim.Render(state) + info
}

func renderHeader(inv Inventory, hosts []Host, loading bool, frame int) string {
	meta := st.Dim.Render(countLabel(len(hosts), "host", "hosts") + " " + glyphDot + " " +
		countLabel(len(inv.Sessions), "session", "sessions"))
	if loading {
		meta = st.Accent.Render(spinnerFrames[frame%len(spinnerFrames)]) + " " +
			st.Dim.Render("asking "+countLabel(len(hosts), "host", "hosts")+"…")
	}
	return " " + st.Title.Render("herd") + "  " + meta
}

func separator(width int) string {
	return st.Dim.Render(strings.Repeat("─", max(width, 1)))
}

// printInventory is `herd ls`: the picker's list, without the picker.
func printInventory(inv Inventory, hosts []Host) {
	nameW := nameWidth(inv)
	var body []string
	for _, r := range buildRows(inv, hosts, "") {
		if r.kind == rowHeading && len(body) > 0 {
			body = append(body, "")
		}
		body = append(body, renderRow(r, nameW, false))
	}
	if len(body) == 0 {
		body = append(body, "   "+st.Dim.Render("no sessions yet — start one with `herd new NAME`"))
	}
	header := renderHeader(inv, hosts, false, 0)
	width := lipgloss.Width(header)
	for _, line := range body {
		width = max(width, lipgloss.Width(line))
	}
	lipgloss.Println("\n" + header + "\n " + separator(width) + "\n" + strings.Join(body, "\n") + "\n")
	if len(hosts) == 1 {
		hint("  only this machine — add others with `herd hosts add NAME [ssh-target]`\n")
	}
}

func printHelp() {
	cmd := func(name, args, desc string) string {
		return "  " + st.Accent.Render(pad(name, 8)) + st.Text.Render(pad(args, 32)) + st.Dim.Render(desc)
	}
	ref := func(example, desc string) string {
		return "  " + st.Text.Render(pad(example, 18)) + st.Dim.Render(desc)
	}
	key := func(k, label string) string { return st.Accent.Render(k) + " " + st.Dim.Render(label) }
	lines := []string{
		"",
		" " + st.Title.Render("herd") + "  " + st.Dim.Render("find, create and attach herdr sessions across your machines"),
		"",
		" " + st.Heading.Render("Usage"),
		"  " + st.Text.Render(pad("herd", 40)) + st.Dim.Render("open the session picker"),
		"  " + st.Text.Render("herd <command>"),
		"",
		" " + st.Heading.Render("Commands"),
		cmd("ls", "[--json]", "every session on every host"),
		cmd("attach", "REF", "attach to exactly one session"),
		cmd("new", "[HOST] NAME [-a]", "start a headless session (-a attaches)"),
		cmd("stop", "REF", "stop a session"),
		cmd("rm", "REF [-y]", "stop and delete a session"),
		cmd("hosts", "[add NAME [TARGET] | rm NAME]", "the machines herd asks"),
		cmd("hub", "[new | add | rm] NAME [REF...]", "a session that also shows chosen sessions"),
		cmd("version", "", "print the version"),
		"",
		" " + st.Heading.Render("References"),
		ref("homelab/agents", "a session on a host"),
		ref("homelab/", "that host's default session"),
		ref("agents", "a session on this machine"),
		ref("hub/overview", "a hub"),
		"",
		" " + st.Heading.Render("Picker"),
		"  " + strings.Join([]string{key("↵", "attach"), key("n", "new"), key("s", "stop"), key("d", "delete"),
			key("/", "filter"), key("r", "refresh"), key("q", "quit")}, "  "),
		"  " + st.Dim.Render("detach from herdr with prefix+q to come back to the picker"),
		"",
	}
	lipgloss.Println(strings.Join(lines, "\n"))
}
