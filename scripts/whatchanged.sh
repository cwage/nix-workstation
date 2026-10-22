#!/usr/bin/env bash
# Show why packages changed between the running system and ./result.
#
# For each package nvd reports as upgraded (or for the names given as
# arguments), print:
#   * what on this system depends on it
#   * the nixpkgs commits between the old and new locked revisions that
#     mention it, with PR links (the PR body is where upstream changelogs
#     are usually linked)
#
# Usage:
#   nixos-rebuild build --flake .#thinkpad
#   scripts/whatchanged.sh            # every version change nvd lists
#   scripts/whatchanged.sh boringssl  # just one package
#
# The old/new nixpkgs revs come from comparing flake.lock in HEAD against
# the working tree, so run this before committing the lock update.
set -euo pipefail

cd "$(dirname "$0")/.."
result=${RESULT:-result}
[ -e "$result" ] || { echo "no ./$result; run nixos-rebuild build first" >&2; exit 1; }

# Collect nixpkgs-ish inputs whose rev changed in the uncommitted lock diff.
declare -A old_rev=() new_rev=()
for input in nixpkgs nixpkgs-unstable; do
  # Root inputs may alias to renamed nodes (e.g. nixpkgs -> nixpkgs_2).
  q=".nodes[.nodes.root.inputs[\"$input\"]].locked.rev // empty"
  o=$(git show HEAD:flake.lock | jq -r "$q")
  n=$(jq -r "$q" flake.lock)
  [ -n "$o" ] && [ -n "$n" ] && [ "$o" != "$n" ] || continue
  old_rev[$input]=$o; new_rev[$input]=$n
done
if [ "${#old_rev[@]}" -eq 0 ]; then
  echo "flake.lock has no uncommitted nixpkgs rev change; nothing to compare against." >&2
fi

# Which packages to look at.
if [ $# -gt 0 ]; then
  pkgs=("$@")
else
  mapfile -t pkgs < <(nvd diff /run/current-system "$result" \
    | awk '/^\[U/ { print $3 }' | grep -v '^nixos-system-' || true)
fi
[ ${#pkgs[@]} -gt 0 ] || { echo "no version changes."; exit 0; }

for pkg in "${pkgs[@]}"; do
  printf '\n=== %s ===\n' "$pkg"
  printf -- '-- used by:\n'
  paths=$(nix-store -qR "$result" | grep -E "^/nix/store/[a-z0-9]{32}-${pkg}-[0-9]" || true)
  if [ -z "$paths" ]; then
    echo "   (not found in closure)"
  else
    for p in $paths; do
      nix-store -q --referrers "$p" | grep -v "^$p\$" \
        | sed -E 's|^/nix/store/[a-z0-9]{32}-|   |' || true
    done | sort -u
  fi

  for input in "${!old_rev[@]}"; do
    printf -- '-- %s commits (%s..%s):\n' "$input" "${old_rev[$input]:0:9}" "${new_rev[$input]:0:9}"
    gh api "repos/NixOS/nixpkgs/compare/${old_rev[$input]}...${new_rev[$input]}" \
      --jq ".commits[] | select(.commit.message | test(\"${pkg}\"; \"i\"))
             | .commit.message | split(\"\n\")[0]" \
      | sed -E 's|\(#([0-9]+)\)|https://github.com/NixOS/nixpkgs/pull/\1|; s|^|   |' \
      || echo "   (gh api failed)"
  done
done
