package main

import (
	"fmt"
	"strings"
	"time"

	"charm.land/bubbles/v2/textinput"
	tea "charm.land/bubbletea/v2"
)

type pickerMode int

const (
	modeList pickerMode = iota
	modeFilter
	modeNewHost
	modeNewName
	modeConfirmDelete
)

type (
	inventoryMsg   struct{ inv Inventory }
	spinMsg        struct{}
	attachReadyMsg struct{ session Session }
	attachDoneMsg  struct {
		session Session
		err     error
	}
	actionDoneMsg struct {
		text   string
		err    error
		attach *Session // attach once the action succeeds
	}
)

type flash struct {
	text string
	err  bool
}

// picker lists every session on every host; enter hands the terminal to herdr and
// detaching (prefix+q) brings you back.
type picker struct {
	hosts         []Host
	inv           Inventory
	loading       bool
	frame         int
	cursor        int // index among session rows
	mode          pickerMode
	filter        textinput.Model
	name          textinput.Model
	hostIdx       int
	pending       Session // awaiting delete confirmation
	flash         flash
	width, height int
}

func newPicker(hosts []Host) picker {
	filter := textinput.New()
	filter.Prompt = ""
	filter.Placeholder = "filter sessions"
	name := textinput.New()
	name.Prompt = ""
	name.Placeholder = "session name"
	return picker{hosts: hosts, loading: true, filter: filter, name: name, width: 80, height: 24}
}

func (m picker) Init() tea.Cmd { return tea.Batch(m.load(), spin()) }

func (m picker) load() tea.Cmd {
	hosts := m.hosts
	return func() tea.Msg { return inventoryMsg{loadInventory(hosts)} }
}

func spin() tea.Cmd {
	return tea.Tick(90*time.Millisecond, func(time.Time) tea.Msg { return spinMsg{} })
}

func (m picker) reload() (tea.Model, tea.Cmd) {
	cmds := []tea.Cmd{m.load()}
	if !m.loading {
		cmds = append(cmds, spin())
	}
	m.loading = true
	return m, tea.Batch(cmds...)
}

func (m picker) sessions() []Session {
	var out []Session
	for _, r := range buildRows(m.inv, m.hosts, m.filter.Value()) {
		if r.kind == rowSession {
			out = append(out, r.session)
		}
	}
	return out
}

func (m picker) selected() (Session, bool) {
	sessions := m.sessions()
	if m.cursor < 0 || m.cursor >= len(sessions) {
		return Session{}, false
	}
	return sessions[m.cursor], true
}

func (m *picker) moveCursor(key string) {
	n := len(m.sessions())
	switch key {
	case "up", "k":
		m.cursor--
	case "down", "j":
		m.cursor++
	case "home", "g":
		m.cursor = 0
	case "end", "G":
		m.cursor = n - 1
	}
	m.cursor = max(0, min(m.cursor, n-1))
}

func (m picker) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case spinMsg:
		if m.loading {
			m.frame++
			return m, spin()
		}
	case inventoryMsg:
		m.inv, m.loading = msg.inv, false
		m.moveCursor("")
	case attachReadyMsg:
		return m, tea.ExecProcess(attachCmd(msg.session), func(err error) tea.Msg {
			return attachDoneMsg{msg.session, err}
		})
	case attachDoneMsg:
		m.flash = flash{text: "back from " + msg.session.Ref()}
		if msg.err != nil {
			m.flash = flash{text: msg.session.Ref() + ": " + msg.err.Error(), err: true}
		}
		return m.reload()
	case actionDoneMsg:
		if msg.err != nil {
			m.flash = flash{text: msg.err.Error(), err: true}
			return m.reload()
		}
		m.flash = flash{text: msg.text}
		if msg.attach != nil {
			s := *msg.attach
			return m, func() tea.Msg { return attachReadyMsg{s} }
		}
		return m.reload()
	case tea.KeyPressMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m picker) handleKey(msg tea.KeyPressMsg) (tea.Model, tea.Cmd) {
	key := msg.String()
	if key == "ctrl+c" {
		return m, tea.Quit
	}
	switch m.mode {
	case modeFilter:
		switch key {
		case "esc", "escape":
			m.filter.Reset()
			m.filter.Blur()
			m.mode = modeList
			m.moveCursor("")
			return m, nil
		case "enter":
			m.filter.Blur()
			m.mode = modeList
			return m, nil
		case "up", "down":
			m.moveCursor(key)
			return m, nil
		}
		var cmd tea.Cmd
		m.filter, cmd = m.filter.Update(msg)
		m.cursor = 0
		return m, cmd

	case modeNewHost:
		switch key {
		case "esc", "escape", "q":
			m.mode = modeList
		case "up", "k":
			m.hostIdx = max(0, m.hostIdx-1)
		case "down", "j":
			m.hostIdx = min(len(m.hosts)-1, m.hostIdx+1)
		case "enter":
			m.mode = modeNewName
			m.name.Reset()
			return m, m.name.Focus()
		}
		return m, nil

	case modeNewName:
		switch key {
		case "esc", "escape":
			m.name.Blur()
			m.mode = modeList
			return m, nil
		case "enter":
			name := strings.TrimSpace(m.name.Value())
			if !nameRE.MatchString(name) {
				m.flash = flash{text: fmt.Sprintf("invalid session name %q — letters, digits, - and _", name), err: true}
				return m, nil
			}
			m.name.Blur()
			m.mode = modeList
			host := m.hosts[m.hostIdx]
			s := Session{Kind: "session", Host: host.Name, Target: host.Target, Name: name}
			m.flash = flash{text: "starting " + s.Ref() + "…"}
			return m, func() tea.Msg {
				if _, err := ensureRunning(s.Target, s.Name); err != nil {
					return actionDoneMsg{err: err}
				}
				return actionDoneMsg{text: "started " + s.Ref(), attach: &s}
			}
		}
		var cmd tea.Cmd
		m.name, cmd = m.name.Update(msg)
		return m, cmd

	case modeConfirmDelete:
		m.mode = modeList
		s := m.pending
		if key != "y" {
			m.flash = flash{text: "kept " + s.Ref()}
			return m, nil
		}
		m.flash = flash{text: "deleting " + s.Ref() + "…"}
		return m, func() tea.Msg { return actionDoneMsg{text: "deleted " + s.Ref(), err: deleteSession(s)} }
	}

	switch key {
	case "q":
		return m, tea.Quit
	case "esc", "escape":
		if m.filter.Value() == "" {
			return m, tea.Quit
		}
		m.filter.Reset()
		m.moveCursor("")
	case "up", "k", "down", "j", "home", "g", "end", "G":
		m.moveCursor(key)
	case "/":
		m.mode = modeFilter
		return m, m.filter.Focus()
	case "r":
		m.flash = flash{}
		return m.reload()
	case "n":
		m.mode, m.hostIdx = modeNewHost, 0
	case "enter":
		if s, ok := m.selected(); ok {
			m.flash = flash{text: "attaching " + s.Ref() + "…"}
			return m, func() tea.Msg {
				if err := prepareAttach(s); err != nil {
					return actionDoneMsg{err: err}
				}
				return attachReadyMsg{s}
			}
		}
	case "s":
		if s, ok := m.selected(); ok && s.Running {
			m.flash = flash{text: "stopping " + s.Ref() + "…"}
			return m, func() tea.Msg {
				_, err := sessionCommand(s.Target, "stop", s.Name)
				return actionDoneMsg{text: "stopped " + s.Ref(), err: err}
			}
		}
	case "d":
		if s, ok := m.selected(); ok {
			if s.Name == defaultSession && !s.IsHub() {
				m.flash = flash{text: "won't delete a default session — stop it instead", err: true}
				return m, nil
			}
			m.pending, m.mode = s, modeConfirmDelete
		}
	}
	return m, nil
}

func (m picker) View() tea.View {
	width := max(m.width, 40)
	body, cursorLine := m.body()
	lines := strings.Split(body, "\n")

	// Keep the cursor row on screen.
	footer := m.footer()
	room := max(m.height-6-strings.Count(footer, "\n"), 3)
	start := max(0, cursorLine-room+1)
	end := min(len(lines), start+room)
	visible := append(lines[start:end:end], make([]string, room-(end-start))...)

	var b strings.Builder
	b.WriteString("\n" + renderHeader(m.inv, m.hosts, m.loading, m.frame) + "\n")
	b.WriteString(" " + separator(width-2) + "\n")
	b.WriteString(strings.Join(visible, "\n") + "\n")
	b.WriteString(" " + separator(width-2) + "\n")
	b.WriteString(footer)

	v := tea.NewView(b.String())
	v.AltScreen = true
	return v
}

// body renders the main area and returns the line the cursor is on.
func (m picker) body() (string, int) {
	switch m.mode {
	case modeNewHost:
		lines := []string{"  " + st.Title.Render("New session") + "  " + st.Dim.Render("where should it run?"), ""}
		for i, h := range m.hosts {
			detail := h.Target
			if h.Name == localHost {
				detail = "this machine"
			}
			if i == m.hostIdx {
				lines = append(lines, "  "+st.Accent.Render(glyphCursor)+"  "+st.Accent.Bold(true).Render(pad(h.Name, 14))+st.Dim.Render(detail))
			} else {
				lines = append(lines, "     "+st.Text.Render(pad(h.Name, 14))+st.Dim.Render(detail))
			}
		}
		return strings.Join(lines, "\n"), 2 + m.hostIdx
	case modeNewName:
		lines := []string{
			"  " + st.Title.Render("New session") + "  " + st.Dim.Render("on "+m.hosts[m.hostIdx].Name),
			"",
			"  " + st.Accent.Render(glyphArrow) + " " + m.name.View(),
			"",
			"  " + st.Dim.Render("starts headless, then attaches · letters, digits, - and _"),
		}
		return strings.Join(lines, "\n"), 2
	}

	rows := buildRows(m.inv, m.hosts, m.filter.Value())
	if len(rows) == 0 {
		msg := "no sessions yet — press n to start one"
		switch {
		case m.loading:
			msg = "looking for sessions…"
		case m.filter.Value() != "":
			msg = "nothing matches “" + m.filter.Value() + "”"
		}
		return "   " + st.Dim.Render(msg), 0
	}
	nameW := nameWidth(m.inv)
	var lines []string
	cursorLine, idx := 0, 0
	for _, r := range rows {
		if r.kind == rowHeading && len(lines) > 0 {
			lines = append(lines, "")
		}
		selected := false
		if r.kind == rowSession {
			selected = idx == m.cursor
			if selected {
				cursorLine = len(lines)
			}
			idx++
		}
		lines = append(lines, renderRow(r, nameW, selected))
	}
	return strings.Join(lines, "\n"), cursorLine
}

func (m picker) footer() string {
	key := func(k, label string) string { return st.Accent.Render(k) + " " + st.Dim.Render(label) }
	var hints []string
	switch m.mode {
	case modeFilter:
		hints = []string{st.Accent.Render("/") + " " + m.filter.View(), key("↵", "done"), key("esc", "clear")}
	case modeNewHost:
		hints = []string{key("↑↓", "choose"), key("↵", "next"), key("esc", "cancel")}
	case modeNewName:
		hints = []string{key("↵", "create & attach"), key("esc", "cancel")}
	case modeConfirmDelete:
		what := "its panes and agents are killed"
		if m.pending.IsHub() {
			what = "its own session is deleted; members are untouched"
		}
		hints = []string{st.Warning.Render(glyphWarning + " delete " + m.pending.Ref() + "? " + what), key("y", "delete"), key("any key", "keep")}
	default:
		hints = []string{key("↵", "attach"), key("n", "new"), key("s", "stop"), key("d", "delete"),
			key("/", "filter"), key("r", "refresh"), key("q", "quit")}
		if f := m.filter.Value(); f != "" {
			hints = append([]string{st.Accent.Render("/") + " " + st.Text.Render(f)}, hints...)
		}
	}
	line := " " + strings.Join(hints, "  ")
	if m.flash.text != "" {
		style, glyph := st.Dim, glyphDot
		if m.flash.err {
			style, glyph = st.Error, glyphCross
		}
		line += "\n " + style.Render(glyph+" "+m.flash.text)
	}
	return line
}
