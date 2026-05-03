# Zsh wrapper. Install sizes.sh as ~/.local/bin/sizes first, then source this file from ~/.zshrc.
sizes() {
    emulate -L zsh
    command sizes "$@"
}
