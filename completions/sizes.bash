# Bash completion for sizes.

_sizes_completion() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$prev" in
        -n|--limit)
            COMPREPLY=( $(compgen -W '10 20 25 40 50 100' -- "$cur") )
            return 0
            ;;
        --sort)
            COMPREPLY=( $(compgen -W 'size files share ext type' -- "$cur") )
            return 0
            ;;
        --format)
            COMPREPLY=( $(compgen -W 'table tsv csv json' -- "$cur") )
            return 0
            ;;
        --group-by)
            COMPREPLY=( $(compgen -W 'ext type' -- "$cur") )
            return 0
            ;;
        --exclude)
            compopt -o dirnames 2>/dev/null
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W '-r --recursive -n --limit -e --exact -E --errors --exclude --sort --format --group-by --plain --no-color --version -h --help' -- "$cur") )
        return 0
    fi

    compopt -o dirnames 2>/dev/null
    COMPREPLY=( $(compgen -d -- "$cur") )
}

complete -F _sizes_completion sizes
