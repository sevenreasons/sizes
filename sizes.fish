# Fish wrapper. Install sizes.sh as ~/.local/bin/sizes first, then source this file from ~/.config/fish/config.fish.
function sizes --description "Show total size by extension"
    command sizes $argv
end
