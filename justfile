# run "just -l" to view all commands

default:
    @just --list

# build clak fcitx5 addon
build:
    cmake --build build

# build in release mode
build-release:
    cmake -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build

# install addon for current user
install:
    cmake --build build --target install-user

# restart fcitx5 daemon
restart:
    fcitx5 -r -d

# build, install and restart fcitx5
dev: build install restart

# run all cargo tests
test-unit:
    cargo test --manifest-path engine/Cargo.toml

# test typing speed and accuracy
test-speed delay="20":
    bash scripts/tests/test_speed.sh {{delay}}

# test chromium address bar typing and backspacing
test-chromium delay="15":
    bash scripts/tests/test_chromium.sh {{delay}}

# test autocomplete selection in address bar
test-autocomplete:
    bash scripts/tests/test_autocomplete_dd.sh

# test user typing scenario
test-scenario:
    bash scripts/tests/test_user_scenario.sh

# run all automated tests
test: test-unit test-scenario

# run all fmt, clippy, unit tests and build check before pushing
check:
    cargo fmt --manifest-path engine/Cargo.toml -- --check
    cargo clippy --manifest-path engine/Cargo.toml -- -D warnings
    cargo test --manifest-path engine/Cargo.toml
    cmake --build build

# install git pre-push hook to run checks before pushing
install-hooks:
    @echo '#!/bin/sh' > .git/hooks/pre-push
    @echo 'echo "Running pre-push checks..."' >> .git/hooks/pre-push
    @echo 'just check || exit 1' >> .git/hooks/pre-push
    @chmod +x .git/hooks/pre-push
    @echo "pre-push hook installed successfully"

# tail debug log
log:
    tail -f /tmp/clak.log

# clear debug log
clean-log:
    rm -f /tmp/clak.log

# create cargo vendor archive for offline packaging
vendor:
    cargo vendor vendor/ --manifest-path engine/Cargo.toml
    tar -czf clak-vendor.tar.gz vendor/
    sha256sum clak-vendor.tar.gz > clak-vendor.tar.gz.sha256
    rm -rf vendor/

# update aur .srcinfo metadata
pkg-aur:
    cd packaging/aur && makepkg --printsrcinfo > .SRCINFO

# generate changelog with git-cliff
changelog:
    git-cliff --unreleased

# test installer simulation flow
test-install mode="":
    bash scripts/install.sh --dry-run {{mode}}

# clean build artifacts
clean:
    rm -rf build engine/target vendor clak-vendor.tar.gz clak-vendor.tar.gz.sha256
