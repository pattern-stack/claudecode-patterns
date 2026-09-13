package main

import (
	"image/color"
	"os"

	"charm.land/lipgloss/v2"
	"github.com/charmbracelet/x/term"
)

// palette mirrors tui-patterns' themes/dark.yml and themes/light.yml, so herd
// reads like the rest of the pattern-stack terminal UIs.
type palette struct {
	Foreground, Dim                  color.Color
	Agent, System, Tool              color.Color
	Success, Error, Warning, Running color.Color
}

var (
	darkPalette = palette{
		Foreground: lipgloss.Color("#F5F5F5"), Dim: lipgloss.Color("#9BA4B5"),
		Agent: lipgloss.Color("#C4A7FF"), System: lipgloss.Color("#A0D8EF"), Tool: lipgloss.Color("#FFCC99"),
		Success: lipgloss.Color("#A8E6CE"), Error: lipgloss.Color("#FF9999"),
		Warning: lipgloss.Color("#FFE6A0"), Running: lipgloss.Color("#C4A7FF"),
	}
	lightPalette = palette{
		Foreground: lipgloss.Color("#2D2B55"), Dim: lipgloss.Color("#8888AA"),
		Agent: lipgloss.Color("#7B5EA7"), System: lipgloss.Color("#3A7CA5"), Tool: lipgloss.Color("#C97B2A"),
		Success: lipgloss.Color("#4A9B6E"), Error: lipgloss.Color("#C4657A"),
		Warning: lipgloss.Color("#B8963E"), Running: lipgloss.Color("#7B5EA7"),
	}
)

// Styles are the resolved tokens herd renders with.
type Styles struct {
	Title, Text, Dim                 lipgloss.Style
	Accent, Heading, Tool            lipgloss.Style
	Success, Error, Warning, Running lipgloss.Style
}

func newStyles(p palette) Styles {
	fg := func(c color.Color) lipgloss.Style { return lipgloss.NewStyle().Foreground(c) }
	return Styles{
		Title:   fg(p.Foreground).Bold(true),
		Text:    fg(p.Foreground),
		Dim:     fg(p.Dim),
		Accent:  fg(p.Agent),
		Heading: fg(p.System),
		Tool:    fg(p.Tool),
		Success: fg(p.Success),
		Error:   fg(p.Error),
		Warning: fg(p.Warning),
		Running: fg(p.Running),
	}
}

// Glyphs shared with pts and tui-patterns.
const (
	glyphCursor  = "›"
	glyphRunning = "●"
	glyphStopped = "○"
	glyphCheck   = "✓"
	glyphCross   = "✗"
	glyphWarning = "⚠"
	glyphArrow   = "→"
	glyphDot     = "·"
)

// spinnerFrames is tui-patterns' SpinnerDense.
var spinnerFrames = []string{"⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"}

// st is the active theme.
var st = newStyles(darkPalette)

// initTheme picks light or dark from the terminal background; HERD_THEME=light|dark overrides it.
func initTheme() {
	switch os.Getenv("HERD_THEME") {
	case "light":
		st = newStyles(lightPalette)
		return
	case "dark":
		return
	}
	if isTerminal(os.Stdin) && isTerminal(os.Stdout) && !lipgloss.HasDarkBackground(os.Stdin, os.Stdout) {
		st = newStyles(lightPalette)
	}
}

func isTerminal(f *os.File) bool { return term.IsTerminal(f.Fd()) }
