# herd — find, create and attach herdr sessions across machines.
# A Go + Bubble Tea binary (building needs Go 1.25+).
# `just herd`                — session picker
# `just herd::install`       — build into ~/.local/bin/herd
# `just herd::deploy <host>` — cross-compile for <host> and copy it over

dir := source_directory()

# Open the session picker
default: build
    @"{{dir}}/bin/herd"

# List every session on every host
ls *args: build
    @"{{dir}}/bin/herd" ls {{args}}

# Build for this machine into tools/herd/bin/
build:
    @cd "{{dir}}" && go build -o bin/herd .

# Build straight into ~/.local/bin/herd
install:
    mkdir -p ~/.local/bin
    rm -f ~/.local/bin/herd
    cd "{{dir}}" && go build -trimpath -o ~/.local/bin/herd .
    @~/.local/bin/herd version

# Cross-compile for <host>'s OS and CPU, then copy it into the host's ~/.local/bin
deploy host:
    #!/usr/bin/env bash
    set -euo pipefail
    platform=$(ssh -o BatchMode=yes {{host}} 'uname -sm')
    case "$platform" in
      "Linux x86_64")                goos=linux  goarch=amd64 ;;
      "Linux aarch64"|"Linux arm64") goos=linux  goarch=arm64 ;;
      "Darwin arm64")                goos=darwin goarch=arm64 ;;
      "Darwin x86_64")               goos=darwin goarch=amd64 ;;
      *) echo "herd: don't know how to build for '$platform'" >&2; exit 1 ;;
    esac
    cd "{{dir}}"
    CGO_ENABLED=0 GOOS=$goos GOARCH=$goarch go build -trimpath -ldflags='-s -w' -o "bin/herd-$goos-$goarch" .
    ssh -o BatchMode=yes {{host}} 'mkdir -p ~/.local/bin && rm -f ~/.local/bin/herd'
    scp -q "bin/herd-$goos-$goarch" {{host}}:.local/bin/herd
    ssh -o BatchMode=yes {{host}} '~/.local/bin/herd version'

# Vet and test
check:
    cd "{{dir}}" && go vet ./... && go test ./...
