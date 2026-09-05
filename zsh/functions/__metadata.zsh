# ============================================================================
# __metadata.zsh — thin zsh shim over the shared bash metadata parser
# ============================================================================
# There is exactly ONE implementation of the cave-* command-surface scan:
# bash/functions/__metadata.sh. It is the single source of truth consumed by
# gen-*-completions, cave-help, and the TUI. Non-bash consumers never port
# that parser — they invoke it via `bash -c`, exactly as stack-tui does
# (bash/scripts/stack-tui, subprocess.run(["bash","-c",'source "$1";
# __stack_metadata', …])). This shim gives zsh the same interface
# (__stack_metadata emits one TSV record per function) with no duplicated
# scan logic, so zsh help/completions can never drift from bash's.
#
# Contract — identical to bash/functions/__metadata.sh:
#   name<TAB>category<TAB>desc<TAB>danger<TAB>complete<TAB>help
#   name     cave-<name> (the function definition)
#   category file basename minus extension
#   desc     the file's first "# desc:" header
#   danger   "danger"|"safe"  complete  "# complete:" spec
#   help     comment block above the def (lines joined with literal "\n")
# ============================================================================

__stack_metadata() {
    # One shared parser lives in the bash tree (bash/functions/__metadata.sh);
    # every port invokes it via `bash -c` (same pattern as stack-tui). This
    # shim points it at the zsh tree so metadata describes zsh's own files:
    #   <repo>/zsh/functions/__metadata.zsh  ->  parser at <repo>/bash, scan
    #   <repo>/zsh/functions with extension zsh.
    local self="${(%):-%x}"
    self="${self:A}"
    local repo zsh_dir meta_sh
    repo="$(cd "${self:h:h:h}" && pwd)"          # <repo>
    zsh_dir="${self:h}"                          # <repo>/zsh/functions
    meta_sh="$repo/bash/functions/__metadata.sh"
    if [ ! -r "$meta_sh" ]; then
        print -u2 "cave-scripts: shared metadata parser not found: $meta_sh"
        return 1
    fi
    bash -c 'source "$1"; __stack_metadata "$2" zsh' _ "$meta_sh" "$zsh_dir"
}
