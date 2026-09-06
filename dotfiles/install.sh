#!/usr/bin/env bash
# ============================================================================
# dotfiles/install.sh — idempotent shell dotfiles + starship installer (D22)
# ============================================================================
# M2 task 7. Wires the three Cave-Scripts loaders + the shared starship
# prompt into the host's dotfiles:
#
#   bash: ~/.bashrc                       + source dotfiles/.bashrc.inc
#   zsh:  ~/.zshrc                        + source dotfiles/.zshrc.inc
#         (comments out the p10k instant-prompt block + ~/.p10k.zsh source)
#   fish: ~/.config/fish/config.fish      ← dotfiles/config.fish
#   all:  $STARSHIP_CONFIG (~/.config/starship.toml) ← dotfiles/starship.toml
#
# Idempotency contract (safe to re-run):
#   - Every managed block is wrapped in BEGIN/END markers; re-running
#     replaces the block in place instead of appending a second copy.
#   - p10k disable lines: only commented out if not already.
#   - Package install only when starship is missing.
#   - Every file it edits gets a timestamped .bak-<date> backup ONCE per run
#     (overwrites only if content actually changes).
#
# The include files are COPIED into $HOME (they reference $HOME/cave/...,
# not the repo checkout, so the repo can move).
#
# Usage:
#   dotfiles/install.sh              # wire everything
#   dotfiles/install.sh --check      # exit 0 if wired, 1 if anything missing
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[SKIP]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME:?HOME must be set}"
STAMP="$(date +%Y%m%d-%H%M%S)"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

# --- Helpers ----------------------------------------------------------------
backup() { # $1=file — one timestamped backup per run, only before first change
    local f="$1"
    [ -f "$f" ] && [ ! -f "$f.bak-$STAMP" ] && cp "$f" "$f.bak-$STAMP"
    return 0
}

# upsert_block <file> <begin-marker> <end-marker> <new-block-file>
# Replaces the marker-delimited block in-place, or appends it. Python does
# the splice: the block replacement is line-array surgery and awk's getline
# redirect dance has bitten this installer before.
upsert_block() {
    local file="$1" begin="$2" end="$3" src="$4"
    backup "$file"
    touch "$file"
    python3 - "$file" "$begin" "$end" "$src" <<'PYSPLICE'
import sys
path, begin, end, src = sys.argv[1:5]
with open(src) as f:
    block = f.read().rstrip('\n').split('\n')
with open(path) as f:
    lines = f.readlines()
out = []
i = 0
replaced = False
while i < len(lines):
    if lines[i].rstrip('\n') == begin:
        out.extend(l + '\n' for l in block)
        replaced = True
        i += 1
        while i < len(lines) and lines[i].rstrip('\n') != end:
            i += 1          # skip old block content
        i += 1              # skip old end marker
    else:
        out.append(lines[i])
        i += 1
if not replaced:
    out.append('\n')
    out.extend(l + '\n' for l in block)
with open(path, 'w') as f:
    f.writelines(out)
PYSPLICE
}

# --- 1. starship package ----------------------------------------------------
if command -v starship >/dev/null 2>&1; then
    log_success "starship installed ($(starship --version | head -1 | awk '{print $2}'))"
else
    if [ "$CHECK_ONLY" -eq 1 ]; then
        log_error "starship not installed"
        exit 1
    fi
    log_info "installing starship (pacman)…"
    sudo pacman -S --needed --noconfirm starship
fi

# --- 2. starship.toml → ~/.config/starship.toml -----------------------------
mkdir -p "$HOME_DIR/.config"
STARSHIP_TOML="$HOME_DIR/.config/starship.toml"
if [ -f "$STARSHIP_TOML" ] && cmp -s "$DOTFILES_DIR/starship.toml" "$STARSHIP_TOML"; then
    log_success "starship.toml current"
else
    if [ "$CHECK_ONLY" -eq 1 ]; then log_error "starship.toml missing/stale"; exit 1; fi
    backup "$STARSHIP_TOML"
    cp "$DOTFILES_DIR/starship.toml" "$STARSHIP_TOML"
    log_success "starship.toml installed → $STARSHIP_TOML"
fi

# --- 3. bash: source .bashrc.inc in ~/.bashrc --------------------------------
BASHRC="$HOME_DIR/.bashrc"
BASHRC_INC="$HOME_DIR/.bashrc.inc"
if [ "$CHECK_ONLY" -eq 0 ]; then
    cp "$DOTFILES_DIR/.bashrc.inc" "$BASHRC_INC"
fi
cat > /tmp/.cave_bash_block.$$ <<'BLOCK'
# >>> cave-scripts bash >>>
[ -r "$HOME/.bashrc.inc" ] && source "$HOME/.bashrc.inc"
# <<< cave-scripts bash <<<
BLOCK
upsert_block "$BASHRC" "# >>> cave-scripts bash >>>" "# <<< cave-scripts bash <<<" /tmp/.cave_bash_block.$$
rm -f /tmp/.cave_bash_block.$$
log_success "bash wiring: $BASHRC sources .bashrc.inc"

# --- 4. zsh: disable p10k, source .zshrc.inc in ~/.zshrc ---------------------
ZSHRC="$HOME_DIR/.zshrc"
ZSHRC_INC="$HOME_DIR/.zshrc.inc"
if [ "$CHECK_ONLY" -eq 0 ]; then
    cp "$DOTFILES_DIR/.zshrc.inc" "$ZSHRC_INC"
fi
if [ "$CHECK_ONLY" -eq 0 ]; then
    # Disable the p10k instant prompt (only if active). The whole 3-line
    # if-block is commented out together so the file stays parseable —
    # commenting only the guard line leaves a dangling `fi`.
    if [ -f "$ZSHRC" ] && grep -q 'p10k' "$ZSHRC"; then
        backup "$ZSHRC"
        python3 - "$ZSHRC" <<'PYEDIT'
import sys
path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()
TAG = '# DISABLED-BY-CAVE-SCRIPTS (starship replaces p10k)'
out = []
in_instant_block = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith('#'):
        out.append(line)
        continue
    if 'p10k-instant-prompt' in line and line.lstrip().startswith('if '):
        in_instant_block = True
        out.append('# ' + line.rstrip('\n') + '  ' + TAG + '\n')
        continue
    if in_instant_block and line.strip() == 'fi':
        in_instant_block = False
        out.append('# ' + line.rstrip('\n') + '  ' + TAG + '\n')
        continue
    if in_instant_block or '.p10k.zsh' in line:
        out.append('# ' + line.rstrip('\n') + '  ' + TAG + '\n')
        continue
    out.append(line)
with open(path, 'w') as f:
    f.writelines(out)
PYEDIT
        log_info "p10k instant prompt disabled in $ZSHRC"
    fi
fi
cat > /tmp/.cave_zsh_block.$$ <<'BLOCK'
# >>> cave-scripts zsh >>>
[[ -r "$HOME/.zshrc.inc" ]] && source "$HOME/.zshrc.inc"
# <<< cave-scripts zsh <<<
BLOCK
upsert_block "$ZSHRC" "# >>> cave-scripts zsh >>>" "# <<< cave-scripts zsh <<<" /tmp/.cave_zsh_block.$$
rm -f /tmp/.cave_zsh_block.$$
log_success "zsh wiring: $ZSHRC sources .zshrc.inc (p10k → starship)"

# --- 5. fish: install config.fish --------------------------------------------
FISH_CFG_DIR="$HOME_DIR/.config/fish"
FISH_CFG="$FISH_CFG_DIR/config.fish"
if [ "$CHECK_ONLY" -eq 0 ]; then
    mkdir -p "$FISH_CFG_DIR"
    if [ -f "$FISH_CFG" ] && ! cmp -s "$DOTFILES_DIR/config.fish" "$FISH_CFG"; then
        backup "$FISH_CFG"
    fi
    cp "$DOTFILES_DIR/config.fish" "$FISH_CFG"
fi
log_success "fish wiring: $FISH_CFG installed"

# --- Summary -----------------------------------------------------------------
echo ""
echo "Shell cutover complete. Open a new shell (bash/zsh/fish) to pick up the"
echo "cave-* surface + starship prompt. Backups: <file>.bak-$STAMP"

if [ "$CHECK_ONLY" -eq 1 ]; then
    # --check falls through only if every gate above passed.
    log_success "check: all dotfiles wired"
fi
