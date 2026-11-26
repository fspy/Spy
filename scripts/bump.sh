#!/usr/bin/env bash
# Start a release: bump the fork counter in Spy.toc and open a CHANGELOG section.
#
#   scripts/bump.sh "what changed" ["another change"]
#
# The version is the only thing the Release workflow reads, so this is the whole
# release step: review the diff, commit, push to main, and CI tags and publishes.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

toc=Spy.toc
changelog=CHANGELOG.md
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

current=$(sed -n 's/^## Version: //p' "$toc" | head -n 1 | tr -d '\r')
if [[ ! $current =~ ^(.+-fspy\.)([0-9]+)$ ]]; then
	echo "bump.sh: no <base>-fspy.N version in $toc (found '$current')" >&2
	exit 1
fi
next="${BASH_REMATCH[1]}$((10#${BASH_REMATCH[2]} + 1))"

if grep -qxF "## $next" "$changelog"; then
	echo "bump.sh: $changelog already has a section for $next" >&2
	exit 1
fi

# Keep a CRLF line ending if the TOC has one: [^\r]* stops before the carriage return.
sed -i "s/^## Version: [^\r]*/## Version: $next/" "$toc"

{
	printf '## %s\n\n' "$next"
	if (($#)); then
		printf -- '- %s\n' "$@"
	else
		printf -- '- TODO: describe this release.\n'
	fi
} > "$tmpdir/section"

# Insert the new section above the most recent one, preserving the file as-is.
awk -v section="$tmpdir/section" '
	!inserted && /^## / {
		while ((getline line < section) > 0) print line
		print ""
		inserted = 1
	}
	{ print }
	END {
		if (!inserted) {
			while ((getline line < section) > 0) print line
		}
	}
' "$changelog" > "$tmpdir/changelog"
mv "$tmpdir/changelog" "$changelog"

printf 'Spy.toc:       %s -> %s\n' "$current" "$next"
printf 'CHANGELOG.md:  added the %s section\n\n' "$next"
printf 'Review the diff, commit, and push to main. The Release workflow checks the\n'
printf 'Lua syntax, tags v%s, and publishes the release.\n' "$next"
