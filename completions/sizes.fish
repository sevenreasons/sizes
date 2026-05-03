# Fish completion for sizes.

complete -c sizes -s r -l recursive -d 'Scan recursively'
complete -c sizes -l depth -d 'Scan up to N directory levels' -x -a '0 1 2 3 4 5'
complete -c sizes -l follow -d 'Follow symlinks'
complete -c sizes -s n -l limit -d 'Show top N rows and combine the rest into OTHER' -x -a '10 20 25 40 50 100'
complete -c sizes -l min-size -d 'Fold rows smaller than SIZE into OTHER' -x -a '1M 10M 100M 1G 10G'
complete -c sizes -l min-share -d 'Fold rows below PCT percent into OTHER' -x -a '0.01 0.1 1 5'
complete -c sizes -s e -l exact -d 'Do not merge extension aliases like JPEG -> JPG'
complete -c sizes -s E -l errors -d 'Print unreadable-path errors after the table'
complete -c sizes -l include -d 'Include matching paths; can be repeated' -r
complete -c sizes -l exclude -d 'Exclude matching paths; can be repeated' -r
complete -c sizes -l type -d 'Include detected type; can be repeated' -x -a 'video image audio archive doc data database model code font 3d binary subs meta game none other'
complete -c sizes -l top-files -d 'Show largest files for extension' -x
complete -c sizes -l sort -d 'Sort output' -x -a 'size files share ext type'
complete -c sizes -l format -d 'Output format' -x -a 'table tsv csv json'
complete -c sizes -l group-by -d 'Group rows' -x -a 'ext type'
complete -c sizes -l plain -d 'Use simple ASCII table'
complete -c sizes -l no-progress -d 'Disable progress animation'
complete -c sizes -l no-color -d 'Disable ANSI colors'
complete -c sizes -l upgrade -d 'Upgrade installed script'
complete -c sizes -l check -d 'With --upgrade, check without installing'
complete -c sizes -l version -d 'Print version; with --upgrade, install tagged version' -x
complete -c sizes -s h -l help -d 'Show help'
