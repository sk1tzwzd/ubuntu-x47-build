# Amnesia (anon) login profile
if [ -n "$BASH_VERSION" ]; then
  [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
fi

# Keep any stray caches out of persistent-looking paths (home is tmpfs anyway).
export XDG_CACHE_HOME="$HOME/.cache"
