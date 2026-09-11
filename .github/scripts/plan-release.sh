#!/usr/bin/env bash
# Decides whether the current main commit warrants a release, and which version
# to cut. Writes `version` to $GITHUB_OUTPUT (empty means nothing to release)
# and the release body to release-notes.md.
set -euo pipefail

skip() {
  echo "::notice::$1"
  echo "version=" >>"$GITHUB_OUTPUT"
  exit 0
}

last=$(git tag -l 'v*' --sort=-v:refname | head -1)
if [ -z "$last" ]; then
  echo "::error::no existing v* tag found; cannot compute the next version"
  exit 1
fi
if [[ ! $last =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "::error::latest tag '$last' is not vMAJOR.MINOR.PATCH"
  exit 1
fi
major=${BASH_REMATCH[1]}
minor=${BASH_REMATCH[2]}
patch=${BASH_REMATCH[3]}

already=$(git tag --points-at HEAD -l 'v*' | paste -sd ' ' -)
if [ -n "$already" ]; then
  skip "$already already points at this commit; assuming it was released by hand"
fi

if ! git merge-base --is-ancestor "$last" HEAD; then
  echo "::warning::$last is not an ancestor of HEAD; release notes may be inaccurate"
fi

# Compare against the last release rather than github.event.before: GitHub keeps
# only one pending run per concurrency group, so a push whose run was dropped
# from the queue must still end up in the next release.
changed=$(git diff --name-only "$last" HEAD -- modules/)
[ -n "$changed" ] || skip "no module changes since $last"

# Labels of the PRs merged since the last release. Walking first parents keeps
# this to one API call per merge/squash commit instead of one per commit.
labels=""
for sha in $(git rev-list --first-parent "$last..HEAD"); do
  labels+=$(gh api "repos/${GITHUB_REPOSITORY}/commits/${sha}/pulls" --jq '.[].labels[].name' 2>/dev/null || true)
  labels+=$'\n'
done

has_label() { grep -qxF "$1" <<<"$labels"; }

if has_label "release:skip"; then
  skip "release:skip label on a PR in this range"
fi

if has_label "release:major"; then
  bump=major
elif has_label "release:minor"; then
  bump=minor
elif has_label "release:patch"; then
  bump=patch
else
  # Conventional commits, read over the whole range so the bump is independent
  # of whether PRs were squashed, rebased or merged.
  subjects=$(git log --format='%s' "$last..HEAD")
  if grep -qE '^[a-z]+(\([^)]*\))?!:' <<<"$subjects" ||
    git log --format='%b' "$last..HEAD" | grep -qE '^BREAKING[ -]CHANGE'; then
    bump=major
  elif grep -qE '^feat(\([^)]*\))?:' <<<"$subjects"; then
    bump=minor
  else
    bump=patch
  fi

  if ! grep -qvE '(^|/)README\.md$' <<<"$changed"; then
    skip "only module docs changed since $last; label a PR release:patch to force a release"
  fi
fi

case $bump in
major) next="v$((major + 1)).0.0" ;;
minor) next="v${major}.$((minor + 1)).0" ;;
patch) next="v${major}.${minor}.$((patch + 1))" ;;
esac

modules=$(cut -d/ -f1-2 <<<"$changed" | sort -u | paste -sd ',' - | sed 's/,/, /g')
changes=$(git log --full-history --no-merges --format='- %s' "$last..HEAD" -- modules/)
[ -n "$changes" ] || changes=$(git log --no-merges --format='- %s' "$last..HEAD")

# One tag covers every module, so a release name says nothing about which
# generated content it carries: v2.2.0 was cut for a GCP change and shipped AWS
# sources from months earlier. List what each module actually contains, for every
# module rather than only the changed ones, since that is the question being asked
# of a tag that did not change the module you care about.
#
# The generated modules stamp the version of the ClickHouse sources they were
# built from onto the resources they create. Match only that shape: provider
# constraints in versions.tf are also spelled `version =`, and `required_version`
# is excluded by anchoring to the start of the line.
contents=""
for dir in modules/*/; do
  name=${dir#modules/}
  name=${name%/}
  # `|| true` because a module without a stamp is the normal case for the
  # hand-maintained ones, and grep finding nothing would otherwise trip set -e.
  embedded=$(grep -hoE '^[[:space:]]*version[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+-[A-Za-z0-9]+"' "$dir"*.tf 2>/dev/null |
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+-[A-Za-z0-9]+' | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g' || true)
  contents+="| \`${name}\` | ${embedded:-not generated} |"$'\n'
done

cat >release-notes.md <<EOF
Automated release. Changed modules: ${modules}

## Module contents

| Module | Generated from |
| --- | --- |
${contents}
\`aws\` and \`aws-per-infra-iam\` are generated from the ClickHouse onboarding
sources and record the version they were built from; the others are maintained
in this repository and carry no such version.

## Changes since ${last}

${changes}

Pin a module with \`?ref=${next}\`; see each module's README for usage.
EOF

echo "version=$next" >>"$GITHUB_OUTPUT"
echo "::notice::releasing $next ($bump bump from $last)"
