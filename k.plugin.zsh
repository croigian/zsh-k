#!/usr/bin/env zsh

# Helper aliases for common options
alias  ka='k  -A'
alias  kd='k  -d'
alias kad='k -Ad'

k() {
    # Helper function to print to stderr
    to_stderr() { echo "$@" >&2; }

    # Print help on bad usage, or when user asks for it
    help() {
        to_stderr 'List information about files and directories.'
        to_stderr
        to_stderr 'Usage: k [OPTIONS] [PATH]'
        to_stderr
        to_stderr 'Options:'
        to_stderr '  -A          show entries with leading "." (except "." and "..")'
        to_stderr '  -d          show directory sizes'
        to_stderr '  -h  --help  show this help'
    }

    # Parse CLI arguments
    local with_hidden= with_directory_sizes= files=() dirs=() has_errors=
    while [ $# -gt 0 ]; do
        while getopts Adh-: option; do
            case "$option" in
                A) with_hidden=1;;
                d) with_directory_sizes=1;;
                h) help && return;;
                -)
                    case "$OPTARG" in
                        help) help && return;;
                        *   ) to_stderr "unknown option: --$OPTARG"; to_stderr; help; return 1;;
                    esac;;
                ?) to_stderr && help && return 1;;
            esac
        done

        # Parsed all parameters passed by caller
        [ "$OPTIND" -gt $# ] && break

        # Advance past processed options, reset index
        shift $((OPTIND - 1)) && OPTIND=1

        # Next argument is positional (not an option), add it to a list of paths if it exists
        if [ -f "$1" ]; then
            files[$(($#files + 1))]=$1
        elif [ -d "$1" ]; then
            dirs[$(($#dirs + 1))]=$1
        else
            to_stderr "k: cannot access '$1': No such file or directory" && has_errors=1
        fi

        # Advance arguments processing by one
        shift
    done

    # Separate error lines from results
    if [ -n "$has_errors" ]; then echo; fi

    # Fetch file info and format the resulting output
    list() {
        # Zip lines from functions, then format them
        paste <(stats $@) <(sizes $@) | awk -F '\t' -v "with_colors=$with_colors" '
            BEGIN { NOW = systime() }

            {
                # Last modification date coloring (shades of white, darker is older)
                time = NOW - $5
                    if (time <           2 * 60 * 60) { date_color = 256 } # Last 2 hours
                else if (time <      7 * 24 * 60 * 60) { date_color = 247 } # Last week
                else if (time < 3 * 30 * 24 * 60 * 60) { date_color = 240 } # Last 3 months
                else                                   { date_color = 237 } # More than 3 months
                date = color(substr($4, 1, 16), date_color)

                # File or directory size coloring
                size_in_bytes = $7
                    if (size_in_bytes < 2 ^ 10) { size_color =  14 } # <=  1 KB, blue
                else if (size_in_bytes < 2 ^ 15) { size_color = 118 } # <= 32 KB, green
                else if (size_in_bytes < 2 ^ 20) { size_color = 226 } # <=  1 MB, yellow
                else if (size_in_bytes < 2 ^ 25) { size_color = 209 } # <= 32 MB, orange
                else if (size_in_bytes < 2 ^ 30) { size_color =   9 } # <=  1 GB, red
                else if (size_in_bytes < 2 ^ 35) { size_color = 124 } # <= 32 GB, dark red
                else                             { size_color =  92 } # >  32 GB, purple

                # Hide empty directory overhead to reduce clutter
                size = (size_in_bytes == -1) ? "" : $6

                type = $2; is_runnable = substr($3, 4, 1)
                    if (type        == "directory"    ) { name_color = bold( 33) } # Dark blue
                else if (type        == "symbolic link") { name_color =       92  } # Purple
                else if (type        == "fifo"         ) { name_color =      226  } # Yellow
                else if (type        == "socket"       ) { name_color =      118  } # Green
                else if (is_runnable == "x"            ) { name_color =        9  } # Red
                else                                     { name_color =      256  } # White
                name = color($1, name_color)

                if (size == -2) { print date, name } else {
                    # ? Color format string to ignore escape codes while right-aligning
                    size_fmt = color("%5s", size_color)

                    printf "%s "size_fmt" %s\n", date, size, name
                }
            }

            # Helper function for color printing
            function color(s, c) { return (with_colors == 1) ? "\033[38;5;"c"m"s"\033[0m" : s }

            # Bold version of a color
            function bold(code) { return code";1" }
        '
    }

    # List file metadata, space-aligned and separated by tabs
    stats() {
        # Detect if there are both regular and hidden files
        has_regular= && has_hidden=
        for entry in "$@"; do
            # Extract name from entry path
            name="${entry##.*/}"

            # Test if first character is a dot
            if [ "${name[1]}" = . ]; then has_hidden=1; else has_regular=1; fi
        done

        # Align names of regular files with a space when displaying both hidden and regular files
        if [ -n "$has_regular" ] && [ -n "$has_hidden" ]; then pad=1; else pad=; fi

        # Fetch file metadata: name, type, permissions, date modified and timestamp
        stat --printf '%n\t%F\t%A\t%y\t%Y\n' "$@"                        | # Get metadata
            if [ -n "$trim" ]; then cut --bytes "$trim-"  ; else cat; fi | # Trim directory name
            if [ -n "$pad"  ]; then sed 's/^/ /;s/^ \././'; else cat; fi   # Align filenames
    }

    # Evaluate size on disk of each entry and format them to be human-readable
    sizes() {
        {
            # Only compute accurate directory sizes if requested
            if [ -n "$with_directory_sizes" ]; then
                du --summarize --block-size 1 --apparent-size "$@" 2> /dev/null | cut --fields 1
            else
                # Hide size column if only directories
                if stat --format %F "$@" | grep --quiet --invert-match '^directory$'
                    then with_only_directories=; else with_only_directories=1; fi

                stat --printf '%F\t%s\n' "$@" | # Retrieve entry type and size
                    awk -F '\t' -v "with_only_directories=$with_only_directories" '{
                        if      (with_only_directories == 1) print  -2 # Hide size column
                        else if ($1 == "directory"         ) print  -1 # Hide directory overhead
                        else                                 print  $2 # Show actual sizes
                    }'
            fi
        }                                         | # Raw size information
            sed --regexp-extended 's/(.*)/\1 \1/' | # Duplicate lines
            numfmt --to iec                       | # Human-readable version for first column
            sed 's/ /\t/'                           # Use tab separator (`numfmt` strips tabs)
    }

    # Only color output when called from an interactive shell
    local with_colors= && if [ -t 1 ]; then with_colors=1; fi

    # Default to current directory if no positional arguments were provided and no unknown paths
    if [ $#files = 0 ] && [ $#dirs = 0 ] && [ -z "$has_errors" ]; then dirs=(.); fi

    # Show details for all files listed, without removing leading directories
    local trim= && if [ $#files != 0 ]; then list $files; if [ $#dirs != 0 ]; then echo; fi; fi

    # Glob flags determine whether hidden files are listed or not
    local glob_options=N && if [ -n "$with_hidden" ]; then glob_options=DN; fi

    # Initialize local loop variables
    local d= i=0

    # Iterate over listed directories
    for d in $dirs; do
        # Show directory name when also listing individual files, or more than one directory
        if [ -n "$has_errors" ] || [ $#files != 0 ] || [ $#dirs != 1 ]; then
            # Color directory name if colored output is enabled
            if [ -n "$with_colors" ]; then
                printf "\033[38;5;33;1m%s\033[0m:\n" "$d"
            else
                echo "$d:"
            fi
        fi

        # Remove directory name from file names
        trim=$(($#d + 2))

        # Use glob expansion to list individual directory entries
        local glob="$d/*($glob_options)"

        # Expand glob to iterate over entries and detect empty directories
        local _entry= is_empty=1; for _entry in $~glob; do is_empty=; done

        # Nothing to do for empty directories
        if [ -z "$is_empty" ]; then list $~glob; fi

        # Track directory index, to suppress newline on last iteration
        i=$((i + 1))

        # Separate directories with a newline, suppress last one
        if [ $i != $#dirs ]; then echo; fi
    done

    # Remove functions from environment to avoid clutter
    unfunction help to_stderr list stats sizes
}
