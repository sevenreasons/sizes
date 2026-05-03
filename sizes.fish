# Fish wrapper for the standalone sizes command.
# Source this file only if you prefer a shell function wrapper.
function sizes --wraps sizes --description 'Pretty disk usage by extension'
    command sizes $argv
end
