# Nushell completion for sizes.

export extern sizes [
    dir?: path
    --recursive(-r)          # Scan recursively
    --limit(-n): int         # Show top N rows and combine the rest into OTHER
    --exact(-e)              # Do not merge extension aliases like JPEG -> JPG
    --errors(-E)             # Print unreadable-path errors after the table
    --exclude: string        # Exclude matching paths; can be repeated
    --sort: string           # Sort by size, files, share, ext, or type
    --format: string         # Output table, tsv, csv, or json
    --group-by: string       # Group by ext or type
    --plain                  # Use simple ASCII table
    --no-progress            # Disable progress animation
    --no-color               # Disable ANSI colors
    --upgrade                # Upgrade installed script
    --version                # Print version
    --help(-h)               # Show help
]
