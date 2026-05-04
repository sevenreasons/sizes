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
        --depth)
            COMPREPLY=( $(compgen -W '0 1 2 3 4 5' -- "$cur") )
            return 0
            ;;
        --max-files)
            COMPREPLY=( $(compgen -W '1000 10000 100000 1000000' -- "$cur") )
            return 0
            ;;
        --min-size)
            COMPREPLY=( $(compgen -W '1M 10M 100M 1G 10G' -- "$cur") )
            return 0
            ;;
        --min-share)
            COMPREPLY=( $(compgen -W '0.01 0.1 1 5' -- "$cur") )
            return 0
            ;;
        --type)
            COMPREPLY=( $(compgen -W 'video image audio archive doc data database model code font 3d binary subs meta game none other' -- "$cur") )
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
        --top-dirs)
            COMPREPLY=( $(compgen -W 'mp4 jpg png webp gguf duckdb parquet zip no_ext' -- "$cur") )
            return 0
            ;;
        --save)
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
        --include|--exclude)
            compopt -o dirnames 2>/dev/null
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W '-r --recursive --depth --follow -x --one-file-system --max-files -n --limit --min-size --min-share -e --exact -E --errors --include --exclude --type --top-files --top-dirs --by-dir -i --interactive --sort --format --save --group-by --plain --no-progress --no-color --upgrade --check --version -h --help' -- "$cur") )
        return 0
    fi

    compopt -o dirnames 2>/dev/null
    COMPREPLY=( $(compgen -d -- "$cur") )
}

complete -F _sizes_completion sizes
