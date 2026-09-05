# ============================================================================
# __metadata.fish — thin fish shim over the shared bash metadata parser
# ============================================================================
# There is exactly ONE implementation of the cave-* command-surface scan:
# bash/functions/__metadata.sh (now fish-aware via its <dir> fish mode). It
# is the single source of truth consumed by gen-*-completions, cave-help,
# and the TUI. Non-bash consumers never port that parser — they invoke it
# via `bash -c`, exactly as stack-tui does. This shim gives fish the same
# interface (__stack_metadata emits one TSV record per function) with no
# duplicated scan logic, so fish help/completions can never drift from
# bash's/zsh's.
#
# Contract — identical to bash/functions/__metadata.sh:
#   name<TAB>category<TAB>desc<TAB>danger<TAB>complete<TAB>help
# ============================================================================

function __stack_metadata --description 'shared cave-* command-surface scan (bash parser, fish tree)'
    # One shared parser lives in the bash tree (bash/functions/__metadata.sh);
    # every port invokes it via `bash -c` (same pattern as stack-tui). This
    # shim points it at the fish tree so metadata describes fish's own files:
    #   <repo>/fish/functions/__metadata.fish  ->  parser at <repo>/bash,
    #   scan <repo>/fish/functions with extension fish.
    set -l self (status filename)
    set -l repo (dirname (dirname (dirname "$self")))
    set -l fish_dir (dirname "$self")
    set -l meta_sh "$repo/bash/functions/__metadata.sh"
    if not test -r "$meta_sh"
        echo "cave-scripts: shared metadata parser not found: $meta_sh" >&2
        return 1
    end
    bash -c 'source "$1"; __stack_metadata "$2" fish' _ "$meta_sh" "$fish_dir"
end
