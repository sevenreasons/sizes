export extern sizes [
    dir?: path          # Directory to scan
    --recursive(-r)     # Scan recursively
    --limit(-n): int    # Show top N extensions and fold the rest into OTHER
    --exact(-e)         # Do not merge aliases like JPEG -> JPG
    --errors(-E)        # Print unreadable-path errors after the table
    --no-color          # Disable ANSI colors
    --version           # Print version
    --help(-h)          # Show help
]
