#!/usr/bin/env zsh

# Helper aliases for common options
alias  ka='k  -A'
alias  kd='k  -d'
alias kad='k -Ad'

k() {
    # Helper logging function
    red() { printf '\033[31m%s\n\033[0m' "$@" >&2; }

    # Parse CLI arguments
    o_ALL= && o_DIRECTORY_SIZES= && o_HELP=
    while getopts 'Adh-:' OPTION 2> /dev/null; do
        case "$OPTION" in
            A ) o_ALL=1;;
            d ) o_DIRECTORY_SIZES=1;;
            h ) o_HELP=1;;
            - )
            case "$OPTARG" in
                help) o_HELP=1;;
                *   ) o_HELP=1; red "Unrecognized long option \"$OPTARG\"!\n";;
            esac;;
            * ) o_HELP=1; red 'Unrecognized short option!\n';;
        esac
    done

    # Print help if bad usage, or user asked for it or bad syntax
    if [ $o_HELP ]; then
        echo 'List information about files (current directory by default)'
        echo
        echo 'Usage: k [OPTIONS] PATHS'
        echo
        echo 'Options:'
        echo '  -A          show entries with leading "." (except "." and "..")'
        echo '  -d          show directory sizes (slow if lots of subdirectories)'
        echo '  -h  --help  show this help'
        return
    fi

    # Shift arguments by number of options parsed
    shift $(( OPTIND - 1 ))

    # Only color output when used in interactive shell
    [ -t 1 ] && COLORS=1 || COLORS=0

    # General information (last modified date, entry type, permissions)
    stats() {
        stat --printf '%Y\t%y\t%F\t%A\n' $@
    }

    # List file names along with targets for symbolic links
    names() {
        SYM_LINK="s/^symbolic link\t(.*)\t['\"]\1['\"] -> ['\"](.*)['\"]$/ \1\t\2/"

        # Align file names if displaying both hidden and regular files
        for f in $@; do echo $f; done | grep -q '/\.[^/]*$'   && # Regular files
        for f in $@; do echo $f; done | grep -q '/[^.][^/]*$' && # Hidden files
        ALIGN=1 || ALIGN=

        stat --printf '%F\t%n\t%N\n' $@          | # File type, name and link target
            sed -E "$SYM_LINK"                   | # Isolate symbolix link target
            sed -E 's/^[^ ].*\t(.*)\t.*$/ \1\t/' | # Remove file types
            sed -E 's/^ //;s/^.*\/(.*)\t/\1\t/'  | # Strip space and input directory
            { [ $ALIGN ] && sed -E 's/^([^.])/ \1/' || cat } # Add leading space
    }

    # Evaluate size on disk of each entry and format them to be human-readable
    sizes() {
        {
            # Only compute accurate directory sizes if requested
            if [ $o_DIRECTORY_SIZES ]; then
                du -s -B1 --apparent-size $@ 2> /dev/null | cut -f 1 # ! Very slow
            else
                # Hide size column if only directories
                stat -c %F $@ | grep -qv '^directory$' && ONLY_DIRS=0 || ONLY_DIRS=1

                stat --printf '%F\t%s\n' $@ | # Retrieve entry type and size
                awk -F '\t' "{
                    if      (  1 ==    $ONLY_DIRS) print  -2 # Hide size column
                    else if (\$1 == \"directory\") print  -1 # Hide directory overhead
                    else                           print \$2 # Show actual sizes
                }"
            fi
        }                          | # Base size information
            sed -E 's/(.*)/\1 \1/' | # Duplicate lines, separated by a space
            numfmt --to=iec        | # Human-readable version for first column
            sed 's/ /\t/'            # Separate columns with tab
    }

    # Zip lines from all data sources and format them in AWK
    K_HOME=${${(%):-%x}%/*}
    show() {
        paste <(stats $@) <(sizes $@) <(names $@) |
            awk -F '\t' -v colors=$COLORS -f "$K_HOME"/combine.awk
    }

    # Display files first, then directories
    FILES=() && DIRS=()
    for entry in $@; do
        # Skip non-existent entries
        [ -f "$entry" ] && FILES+=("$entry")
        [ -d "$entry" ] &&  DIRS+=("$entry")
    done

    # Display files with no newlines, before directories
    if [ $#FILES != 0 ]; then show $FILES; fi

    # Print newline if both a files section and directories section
    [ $#FILES != 0 ] && [ $#DIRS != 0 ] && echo

    # Add current directory if no inputs specified
    [ $# = 0 ] && DIRS=(.)

    # Print newline except for last directory
    newline() { if [ $i != $#DIRS ]; then echo && i=$(( $i + 1 )); fi }

    # Loop through input directories
    i=1
    for dir in $DIRS; do
        # Display directory name if at least one file or multiple directories
        { [ $#FILES != 0 ] || [ $#DIRS != 1 ] } && echo $dir | sed 's|/$||;s/$/:/'

        # Skip non-existent and empty directory inputs
        [ ! $o_ALL ] && [ ! "$(ls    $dir)" ] && newline && continue
        [   $o_ALL ] && [ ! "$(ls -A $dir)" ] && newline && continue

        # Include hidden files if requested
        [ $o_ALL ] && FILES="$dir"/*(D) || FILES="$dir"/*

        # Display directory contents
        show $~FILES

        # Print newline to separate directories
        newline
    done
}
