package main

import (
	"bytes"
	"context"
	"errors"
	"os/exec"
	"strings"
	"time"
)

// Non-interactive SSH shells often miss the dirs herdr installs into.
const shPath = `export PATH="$HOME/.local/bin:$HOME/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"` + "\n"

func shQuote(s string) string { return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'" }

// runOn runs a POSIX sh script on this machine (target "") or over SSH, passing args as $1...
func runOn(target, script string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	argv := append([]string{"sh", "-c", script, "herd"}, args...)
	var cmd *exec.Cmd
	if target == "" {
		cmd = exec.CommandContext(ctx, argv[0], argv[1:]...)
	} else {
		quoted := make([]string, len(argv))
		for i, a := range argv {
			quoted[i] = shQuote(a)
		}
		cmd = exec.CommandContext(ctx, "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
			target, strings.Join(quoted, " "))
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		if ctx.Err() != nil {
			return stdout.String(), errors.New("timed out")
		}
		return stdout.String(), errors.New(lastLine(stderr.String(), err.Error()))
	}
	return stdout.String(), nil
}

func lastLine(s, fallback string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	if last := strings.TrimSpace(lines[len(lines)-1]); last != "" {
		return last
	}
	return fallback
}
