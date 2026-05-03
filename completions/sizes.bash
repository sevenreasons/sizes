_sizes_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="-r --recursive -n --limit -e --exact -E --errors --no-color --version -h --help"

    if [[ "$prev" == "-n" || "$prev" == "--limit" ]]; then
        COMPREPLY=( $(compgen -W "10 20 30 40 50 100" -- "$cur") )
        return 0
    fi

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi

    COMPREPLY=( $(compgen -d -- "$cur") )
}
complete -F _sizes_completion sizes
