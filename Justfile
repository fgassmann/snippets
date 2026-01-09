#!/usr/bin/env just --justfile

set unstable

# -> build
[group('common')]
default: help

# Push to main
[group('git')]
push:
    git push origin main

# Fetch and pull
[group('git')]
pull:
    git fetch --all
    git pull


# fetch external snippets for the helix snippet lsp
[group('common')]
build:
    simple-completion-language-server fetch-external-snippets
    simple-completion-language-server validate-snippets


# List all the just commands
[group('common')]
help:
    @just --list

