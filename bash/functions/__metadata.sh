# ============================================================================
# __metadata.sh — single source of truth for the cave-* command surface
# ============================================================================
# Consumed by gen-bash-completions.sh, cave-help, stack-tui, and the drift
# tests, so every surface derives name/category/desc/danger/complete/help
# from ONE scan instead of four independent parsers.
#
# Contract — `__stack_metadata` prints one TSV record per function:
#   name<TAB>category<TAB>desc<TAB>danger<TAB>complete<TAB>help
#   name     cave-<name> (the function definition)
#   category file basename minus .sh (cave-arr-1, cave-plex-core, ...)
#   desc     the file's first "# desc:" header (same for all fns in a file)
#   danger   "danger" if the body mutates the stack (heuristic signals,
#            or an explicit in-body "# danger: true" directive), else "safe"
#   complete the function's "# complete:" spec (first in-body directive)
#   help     comment block above the def, minus "# ===" separators, each
#            line stripped of leading '#'/spaces and trailing whitespace,
#            joined with a literal two-char "\n"
#
# Records are emitted in sorted file order, functions in file order.
# A directive binds to the function whose BODY contains it — a directive in
# the help block above a def (outside the body) is not picked up; keep
# "# complete:" as the first line of the function body.
# ============================================================================

# One parser for every port. `__stack_metadata` scans whichever functions
# directory it is pointed at, so bash/zsh/fish share this single scan
# implementation instead of each porting its own:
#   __stack_metadata              # default: this file's dir, *.sh (bash tree)
#   __stack_metadata <dir> <ext>  # e.g. zsh dir + "zsh", fish dir + "fish"
# Non-bash consumers (cave-help in zsh/fish, stack-tui, completion
# generators) invoke this via `bash -c 'source "$1"; __stack_metadata …'`.
#
# Port syntax (selected by <ext>):
#   sh/zsh:  def = `cave-<name>() {`; body ends at a column-0 `}`;
#            directives bind as the first in-body lines.
#   fish:    def = `function cave-<name> …`; body ends at the matching
#            column-0 `end` — tracked with a depth counter, because fish
#            bodies legitimately contain nested `end` keywords (if/for/
#            while/switch/function blocks). `# complete:`/`# danger:`
#            directives sit inside the body exactly as in the other ports.
__stack_metadata() {
    local fn_dir="${1:-}"
    [ -n "$fn_dir" ] || fn_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local ext="${2:-sh}"
    local f
    for f in "$fn_dir"/cave-*."$ext"; do
        [ -r "$f" ] || continue
        local category desc line
        category="$(basename "$f" ".$ext")"
        desc="$(grep -m1 -o '# desc: .*' "$f" 2>/dev/null | sed 's/^# desc: //')"
        local -a lines=()
        while IFS= read -r line; do
            lines+=("$line")
        done < "$f"
        local i=0 n="${#lines[@]}"
        while [ "$i" -lt "$n" ]; do
            if [ "$ext" = fish ]; then
                # fish def line: `function cave-<name> …` at column 0.
                # Body scan runs to the matching column-0 `end` (depth-aware).
                if [[ "${lines[$i]}" =~ ^function[[:space:]]+(cave-[a-z0-9-]+)([[:space:]].*)?$ ]]; then
                local name="${BASH_REMATCH[1]}"
                # --- help: contiguous comment block above the def ----------
                local -a help_lines=()
                local j=$((i - 1))
                while [ "$j" -ge 0 ] && [[ "${lines[$j]}" == \#* ]]; do
                    if ! [[ "${lines[$j]}" =~ ^#[[:space:]]*=+$ ]]; then
                        local h="${lines[$j]}"
                        h="${h#"${h%%[!# ]*}"}"
                        h="${h%"${h##*[![:space:]]}"}"
                        help_lines=("$h" "${help_lines[@]}")
                    fi
                    j=$((j - 1))
                done
                # --- body: until the matching column-0 `end` ---------------
                # fish opens a block with `function`, so the body depth starts
                # at 1; every block opener at column 0 (`for`/`while`/`if`/
                # `switch`/`function`) increments it, a column-0 `end`
                # decrements it, and the def's own body closes when depth
                # returns to 0. Embedded python (python3 -c "…") also emits
                # column-0 `if/for/while` lines — but python block openers
                # always end with `:` while fish openers never do, so
                # `:`-terminated lines are skipped to keep the depth true.
                local -a body=()
                local k=$((i + 1)) depth=1
                while [ "$k" -lt "$n" ]; do
                    local bl="${lines[$k]}"
                    if [[ "$bl" == end ]]; then
                        depth=$((depth - 1))
                        [ "$depth" -le 0 ] && break
                    elif [[ "$bl" != *: && "$bl" =~ ^(for|while|if|switch|function)([[:space:]].*)?$ ]]; then
                        depth=$((depth + 1))
                    fi
                    body+=("$bl")
                    k=$((k + 1))
                done
                # --- complete: first in-body directive ----------------------
                local complete="" dl
                for dl in "${body[@]}"; do
                    if [[ "$dl" =~ ^#[[:space:]]*complete:[[:space:]]*(.+)$ ]]; then
                        complete="${BASH_REMATCH[1]}"
                        complete="${complete%"${complete##*[![:space:]]}"}"
                        break
                    fi
                done
                # --- danger: explicit annotation overrides the heuristic ---
                local danger="safe"
                for dl in "${body[@]}"; do
                    if [[ "$dl" =~ ^#[[:space:]]*danger:[[:space:]]*(true|yes) ]]; then
                        danger="danger"
                        break
                    fi
                done
                if [ "$danger" = safe ]; then
                    local body_text
                    body_text="$(printf '%s\n' "${body[@]}")"
                    if grep -Eq 'STACK_API_TIMEOUT_MUTATE| -X (POST|PUT|DELETE)|method=.POST.|method=.PUT.|method=.DELETE.|--force|compose (restart|stop|rm|down|up|recreate)|rm -|truncate|emptyTrash|clear-blocklist' <<<"$body_text"; then
                        danger="danger"
                    fi
                fi
                # --- help join: literal backslash-n -------------------------
                local help=""
                if [ "${#help_lines[@]}" -gt 0 ]; then
                    help="$(printf '%s\\n' "${help_lines[@]}")"
                    help="${help%\\n}"
                fi
                printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                    "$name" "$category" "$desc" "$danger" "$complete" "$help"
                i=$k
                else
                    i=$((i + 1))
                fi
                continue
            fi
            if [[ "${lines[$i]}" =~ ^(cave-[a-z0-9-]+)\(\)[[:space:]]*\{ ]]; then
                local name="${BASH_REMATCH[1]}"
                # --- help: contiguous comment block above the def ----------
                local -a help_lines=()
                local j=$((i - 1))
                while [ "$j" -ge 0 ] && [[ "${lines[$j]}" == \#* ]]; do
                    if ! [[ "${lines[$j]}" =~ ^#[[:space:]]*=+$ ]]; then
                        local h="${lines[$j]}"
                        # strip leading '#'/' ' chars (python lstrip("# ")),
                        # then trailing whitespace (python rstrip()).
                        h="${h#"${h%%[!# ]*}"}"
                        h="${h%"${h##*[![:space:]]}"}"
                        help_lines=("$h" "${help_lines[@]}")
                    fi
                    j=$((j - 1))
                done
                # --- body: until the next def or a column-0 '}' ------------
                local -a body=()
                local k=$((i + 1))
                while [ "$k" -lt "$n" ] \
                      && ! [[ "${lines[$k]}" =~ ^(cave-[a-z0-9-]+)\(\)[[:space:]]*\{ ]] \
                      && [ "${lines[$k]}" != "}" ]; do
                    body+=("${lines[$k]}")
                    k=$((k + 1))
                done
                # --- complete: first in-body directive ----------------------
                local complete="" bl
                for bl in "${body[@]}"; do
                    if [[ "$bl" =~ ^#[[:space:]]*complete:[[:space:]]*(.+)$ ]]; then
                        complete="${BASH_REMATCH[1]}"
                        complete="${complete%"${complete##*[![:space:]]}"}"
                        break
                    fi
                done
                # --- danger: explicit annotation overrides the heuristic ---
                # "# danger: true" (or yes) as an in-body directive forces the
                # flag even when no mutation signal is visible (e.g. helpers
                # like __plex_butler that POST server-side). The signal list
                # below is the fallback for unannotated functions.
                local danger="safe" dl
                for dl in "${body[@]}"; do
                    if [[ "$dl" =~ ^#[[:space:]]*danger:[[:space:]]*(true|yes) ]]; then
                        danger="danger"
                        break
                    fi
                done
                if [ "$danger" = safe ]; then
                    local body_text
                    body_text="$(printf '%s\n' "${body[@]}")"
                    if grep -Eq 'STACK_API_TIMEOUT_MUTATE| -X (POST|PUT|DELETE)|method=.POST.|method=.PUT.|method=.DELETE.|--force|compose (restart|stop|rm|down|up|recreate)|rm -|truncate|emptyTrash|clear-blocklist' <<<"$body_text"; then
                        danger="danger"
                    fi
                fi
                # --- help join: literal backslash-n -------------------------
                local help=""
                if [ "${#help_lines[@]}" -gt 0 ]; then
                    help="$(printf '%s\\n' "${help_lines[@]}")"
                    help="${help%\\n}"
                fi
                printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                    "$name" "$category" "$desc" "$danger" "$complete" "$help"
                i=$k
            else
                i=$((i + 1))
            fi
        done
    done
}
