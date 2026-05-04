# Nushell completion for sizes.

export extern sizes [
    dir?: path
    --recursive(-r)          # Scan recursively
    --depth: int             # Scan up to N directory levels
    --follow                 # Follow symlinks
    --one-file-system(-x)    # Do not cross filesystem boundaries
    --max-files: int         # Stop after N scanned files
    --limit(-n): int         # Show top N rows and combine the rest into OTHER
    --min-size: string       # Fold rows smaller than SIZE into OTHER
    --min-share: number      # Fold rows below PCT percent into OTHER
    --exact(-e)              # Do not merge extension aliases like JPEG -> JPG
    --errors(-E)             # Print unreadable-path errors after the table
    --include: string        # Include matching paths; can be repeated
    --exclude: string        # Exclude matching paths; can be repeated
    --type: string           # Include detected type; can be repeated
    --top-files: string      # Show largest files for extension
    --top-dirs: string       # Show directories using the most space, optionally for extension
    --by-dir                 # Summarize by immediate child directory
    --interactive(-i)        # Open the fzf interactive browser
    --interactive-no-preview  # Start interactive mode with preview hidden
    --sort: string           # Sort by size, files, share, ext, or type
    --format: string         # Output table, tsv, csv, or json
    --save: path             # Save output to file
    --group-by: string       # Group by ext or type
    --plain                  # Use simple ASCII table
    --no-progress            # Disable progress animation
    --no-color               # Disable ANSI colors
    --upgrade                # Upgrade installed script
    --check                  # With --upgrade, check without installing
    --version: string        # Print version; with --upgrade, install tagged version
    --help(-h)               # Show help
]
