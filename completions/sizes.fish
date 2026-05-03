# Fish completion for sizes.

complete -c sizes -s r -l recursive -d 'Scan recursively'
complete -c sizes -s n -l limit -d 'Show top N rows and combine the rest into OTHER' -x -a '10 20 25 40 50 100'
complete -c sizes -s e -l exact -d 'Do not merge extension aliases like JPEG -> JPG'
complete -c sizes -s E -l errors -d 'Print unreadable-path errors after the table'
complete -c sizes -l exclude -d 'Exclude matching paths; can be repeated' -r
complete -c sizes -l sort -d 'Sort output' -x -a 'size files share ext type'
complete -c sizes -l format -d 'Output format' -x -a 'table tsv csv json'
complete -c sizes -l group-by -d 'Group rows' -x -a 'ext type'
complete -c sizes -l plain -d 'Use simple ASCII table'
complete -c sizes -l no-progress -d 'Disable progress animation'
complete -c sizes -l no-color -d 'Disable ANSI colors'
complete -c sizes -l upgrade -d 'Upgrade installed script'
complete -c sizes -l version -d 'Print version'
complete -c sizes -s h -l help -d 'Show help'
