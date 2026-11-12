#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIGURATION
# =========================

# External device mount point.
# Change the last part to your pendrive/external drive name.
DEVICE_DEST="/run/media/$USER/Ventoy"

# Main backups folder inside the external device.
BACKUPS_DIR="$DEVICE_DEST/back-ups"

# Dated backup folder.
BACKUP_NAME="backup-$(date +%F)"

# Final backup destination:
# Example: /run/media/daya/MyBackupDrive/back-ups/backup-2026-05-06
BACKUP_DEST="$BACKUPS_DIR/$BACKUP_NAME"

# Your programming/code folder.
PROGRAMMING_DIR="$HOME/programming"

# Home folders to back up normally.
HOME_FOLDERS=(
  "Desktop"
  "Documents"
  # "Downloads"
  "Music"
  "Pictures"
  "Videos"
)

# Hidden files/folders to back up.
DOTFILES=(
  ".bashrc"
  ".zshrc"
  ".profile"
  ".bash_profile"
  ".gitconfig"
  # ".config"
  ".ssh/config"
)

# Use DRY_RUN=true to test without copying.
DRY_RUN=false

# Set to true if you want destination to mirror source and delete removed files.
# Be careful with this.
DELETE_REMOVED=false


# =========================
# INTERNAL SETTINGS
# =========================

RSYNC_FLAGS=(-a --no-links --info=progress2)

if [ "$DRY_RUN" = true ]; then
  RSYNC_FLAGS+=(--dry-run)
fi

if [ "$DELETE_REMOVED" = true ]; then
  RSYNC_FLAGS+=(--delete)
fi

mkdir -p "$BACKUP_DEST"


# =========================
# FUNCTIONS
# =========================

copy_normal_folder() {
  local folder_name="$1"
  local source="$HOME/$folder_name"
  local dest="$BACKUP_DEST/$folder_name"

  if [ -d "$source" ]; then
    echo "Backing up normal folder: $source"
    mkdir -p "$dest"
    rsync "${RSYNC_FLAGS[@]}" "$source/" "$dest/"
  else
    echo "Skipping missing folder: $source"
  fi
}

copy_dotfile() {
  local item="$1"
  local source="$HOME/$item"
  local dest="$BACKUP_DEST/$item"

  if [ -e "$source" ]; then
    echo "Backing up hidden item: $source"
    mkdir -p "$(dirname "$dest")"

    if [ -d "$source" ]; then
      rsync "${RSYNC_FLAGS[@]}" "$source/" "$dest/"
    else
      rsync "${RSYNC_FLAGS[@]}" "$source" "$dest"
    fi
  else
    echo "Skipping missing hidden item: $source"
  fi
}

backup_git_repo() {
  local repo="$1"
  local root="$2"

  local relative_path
  relative_path="$(realpath --relative-to="$root" "$repo")"

  local dest="$BACKUP_DEST/programming/$relative_path"

  echo "Backing up Git-aware repo: $repo"
  mkdir -p "$dest"

  (
    cd "$repo"

    # Copies:
    # - tracked files
    # - untracked files that are NOT ignored
    # - check if files exists, because git persists deleted files
    #
    # Skips:
    # - files ignored by .gitignore
    # - node_modules/
    # - venv/
    # - vendor/
    # - *.mp4 if listed in .gitignore
    # - other ignored data/cache/build files
    git ls-files -co --exclude-standard -z |
      while IFS= read -r -d '' file; do
        if [ -e "$file" ]; then
          printf '%s\0' "$file"
        fi
      done |
      rsync "${RSYNC_FLAGS[@]}" --from0 --files-from=- ./ "$dest/"
  )
}

backup_programming_folder() {
  local root="$1"

  if [ ! -d "$root" ]; then
    echo "Skipping programming folder because it does not exist: $root"
    return
  fi

  echo "Scanning programming folder: $root"

  # Find Git repositories.
  mapfile -t repos < <(
    find "$root" -type d -name ".git" -prune -print |
      sed 's|/.git$||'
  )

  if [ "${#repos[@]}" -eq 0 ]; then
    echo "No Git repositories found. Backing up programming folder with common exclusions."

    rsync "${RSYNC_FLAGS[@]}" \
      --exclude=".git/" \
      --exclude="node_modules/" \
      --exclude="venv/" \
      --exclude=".venv/" \
      --exclude="vendor/" \
      --exclude="__pycache__/" \
      --exclude=".pytest_cache/" \
      --exclude=".mypy_cache/" \
      --exclude="dist/" \
      --exclude="build/" \
      --exclude="*.mp4" \
      "$root/" "$BACKUP_DEST/programming/"

    return
  fi

  for repo in "${repos[@]}"; do
    backup_git_repo "$repo" "$root"
  done

  echo "Finished Git-aware programming backup."
}


# =========================
# MAIN BACKUP
# =========================

echo "Starting backup to: $BACKUP_DEST"
echo

for folder in "${HOME_FOLDERS[@]}"; do
  copy_normal_folder "$folder"
done

echo

for item in "${DOTFILES[@]}"; do
  copy_dotfile "$item"
done

echo

backup_programming_folder "$PROGRAMMING_DIR"

echo
echo "Backup finished."
