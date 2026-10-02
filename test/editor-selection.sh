#!/usr/bin/env bash
# Which editor does `gh lab` open, and does it say so when it can't?
#
# Runs the REAL gh-lab main path end to end against stubbed `gh`, `curl` and
# editors, in a throwaway HOME. Nothing here touches your git config, your
# editor, or GitHub.
#
#   ./test/editor-selection.sh
#
# PATH is deliberately cut down to /usr/bin:/bin plus the stubs. A real `code`
# usually lives in /usr/local/bin, and leaving it reachable made the
# "no editor installed" case silently drive the real one -- a passing test that
# was not testing anything.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LAB="${LAB_SCRIPT:-$HERE/../gh-lab}"
WORK="${TMPDIR:-/tmp}/gh-lab-test.$$"
PASS=0; FAIL=0

trap 'rm -rf "$WORK"' EXIT

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

# --- stubs ------------------------------------------------------------------
write_stubs() {
  local bin="$1"
  mkdir -p "$bin"

  cat > "$bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") [ "${3:-}" = --active ] && echo "Token scopes: 'admin:org', 'repo'"; exit 0 ;;
  "student --help") exit 0 ;;
  "extension list") echo "gh  student  foundation50/gh-student  v1.34.1"; exit 0 ;;
esac
if [ "$1" = api ]; then
  shift; path="$1"; shift
  case "$path" in
    user) echo teststudent; exit 0 ;;
    user/repository_invitations) exit 0 ;;
    repos/*/commits*) echo 1; exit 0 ;;
    repos/*/collaborators/*) exit 0 ;;
    repos/*)
      name="${path#repos/}"
      [ -f "$T/created" ] && [ "$(cat "$T/created")" = "$name" ] || exit 1
      for a in "$@"; do case "$a" in
        .full_name) echo "$name"; exit 0 ;;
        .created_at) echo "2026-01-01T00:00:00Z"; exit 0 ;;
      esac; done
      exit 0 ;;
  esac
  exit 1
fi
[ "$1 $2" = "student accept" ] && { printf '%s/%s-%s-teststudent' "$3" "$4" "$5" > "$T/created"; exit 0; }
[ "$1 $2" = "repo clone" ] && { git clone -q "$T/origin.git" "$4"; exit $?; }
exit 1
EOF

  cat > "$bin/curl" <<'EOF'
#!/usr/bin/env bash
# Records the EDITOR a child process actually sees -- this is what proves the
# script no longer overwrites the user's own EDITOR on its way past.
printf 'EDITOR=[%s]\n' "${EDITOR-<unset>}" >> "$T/child-env.log"
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; http*) url="$1"; shift ;; *) shift ;; esac
done
case "$url" in
  *assignments.json) printf '[{"slug": "lab-loops-1", "mode": "individual"}]'; exit 0 ;;
  *raik-style.xml)   [ -n "$out" ] && printf '<module name="Checker"/>\n' > "$out"; exit 0 ;;
  *.vsix)            [ -n "$out" ] && printf 'FAKEVSIX' > "$out"; exit 0 ;;
esac
exit 1
EOF

  cat > "$bin/_editor" <<'EOF'
#!/usr/bin/env bash
me="$(basename "$0")"
case "$1" in
  --list-extensions)   [ -f "$T/$me.ext" ] && cat "$T/$me.ext"; exit 0 ;;
  --install-extension) printf '%s\n' "$2" >> "$T/$me.ext"; exit 0 ;;
esac
printf '%s\n' "$me" >> "$T/opened.log"
exit 0
EOF
  chmod +x "$bin/gh" "$bin/curl" "$bin/_editor"
}

# --- one scenario -----------------------------------------------------------
# run <name> <editors-present> <pref|-> [extra env...]
# Leaves $T set, so a caller can inspect $T/opened.log and $T/out.
run() {
  local name="$1" present="$2" pref="$3"; shift 3
  T="$WORK/$name"; export T
  mkdir -p "$T/bin" "$T/home/.config" "$T/course"

  git init -q --bare "$T/origin.git"
  git init -q "$T/seed"
  ( cd "$T/seed" && mkdir -p src && echo 'class Main {}' > src/Main.java \
    && git -c user.email=t@t -c user.name=t add -A \
    && git -c user.email=t@t -c user.name=t commit -qm init \
    && git branch -M main && git remote add origin "$T/origin.git" \
    && git push -q origin main ) >/dev/null 2>&1

  write_stubs "$T/bin"
  local e; for e in $present; do cp "$T/bin/_editor" "$T/bin/$e"; done

  HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" \
    git config --global user.email t@t
  HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" \
    git config --global raik.coursedir "$T/course"
  [ "$pref" != "-" ] && HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" \
    git config --global raik.ide "$pref"

  env -i T="$T" HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" \
      PATH="$T/bin:/usr/bin:/bin" RAIK_NO_UPDATE=1 "$@" \
      bash "$LAB" lab-loops-1 > "$T/out" 2>&1
}

# Empty when nothing was opened -- the file only exists if a stub editor ran.
opened()  { [ -f "$T/opened.log" ] || return 0; tr '\n' ' ' < "$T/opened.log" | sed 's/ $//'; }
check()   { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then green "  PASS  $1"; PASS=$((PASS+1))
  else red "  FAIL  $1"; red "          expected: [$2]"; red "          actual:   [$3]"; FAIL=$((FAIL+1)); fi
}
says()    { # says <description> <substring>
  # -- or a pattern starting with a dash is read as an option, and the test fails
  # for its own reasons rather than the script's.
  if grep -qF -- "$2" "$T/out"; then green "  PASS  $1"; PASS=$((PASS+1))
  else red "  FAIL  $1 -- output never said: $2"; FAIL=$((FAIL+1)); fi
}

printf '\nEditor selection (%s)\n\n' "$LAB"

echo "no preference set -- unchanged from before --ide existed"
run nopref-both "cursor code" -
check "both installed: Cursor wins (the course default)" "cursor" "$(opened)"
run nopref-code "code" -
check "only VS Code installed: VS Code" "code" "$(opened)"

echo
echo "a saved preference decides it"
run pref-code "cursor code" code
check "--ide vscode beats Cursor-first" "code" "$(opened)"
check "extensions go to the chosen editor" "code" "$(head -1 "$T/code.ext" >/dev/null 2>&1 && echo code)"
run pref-cursor "cursor code" cursor
check "--ide cursor still works" "cursor" "$(opened)"

echo
echo "a preference whose command is missing is reported, never swapped"
run pref-missing "code" cursor
check "nothing is opened" "" "$(opened)"
says  "names the editor you chose" "You picked cursor"
says  "tells you how to fix it"    "Install 'cursor' command"
says  "offers the way out"         "--ide auto"

echo
echo "no editor at all"
run no-editor "" -
check "nothing is opened" "" "$(opened)"
says  "names both commands" "No 'cursor' or 'code' command"
run no-editor-pref "" code
says  "a VS Code preference gets VS Code's own instructions" "Shell Command: Install 'code' command in PATH"

echo
echo "the user's own \$EDITOR is left alone"
run keeps-editor "cursor code" - EDITOR=emacs
check "a child process still sees EDITOR=emacs" "EDITOR=[emacs]" "$(sort -u "$T/child-env.log" | tr '\n' ' ' | sed 's/ $//')"

echo
echo "running it twice"
run rerun "cursor code" code
env -i T="$T" HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" \
    PATH="$T/bin:/usr/bin:/bin" RAIK_NO_UPDATE=1 bash "$LAB" lab-loops-1 >/dev/null 2>&1
check "second run opens the same editor" "code code" "$(opened)"

printf '\n%s passed, %s failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
