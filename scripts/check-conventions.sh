#!/bin/sh
# Checks the repository rules that need no build: Swift files stay within 250
# lines, and no generated or local file is committed. Run from the repository root.
set -eu

status=0

long=$(git ls-files 'App/*.swift' 'Sources/*.swift' 'Tests/*.swift' | while IFS= read -r file; do
    lines=$(wc -l < "$file" | tr -d ' ')
    if [ "$lines" -gt 250 ]; then
        echo "  $file ($lines lines)"
    fi
done)
if [ -n "$long" ]; then
    echo "Swift files over 250 lines. Split them (see AGENTS.md, section 5):"
    echo "$long"
    status=1
fi

generated=$(git ls-files | grep -E '^(Kiln\.xcodeproj|build|\.build|DerivedData|\.swiftpm)/|(^|/)xcuserdata/|(^|/)\.DS_Store$' || true)
if [ -n "$generated" ]; then
    echo "Generated or local files are committed. Remove them (see AGENTS.md, section 3):"
    echo "$generated" | sed 's/^/  /'
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "OK"
fi
exit "$status"
