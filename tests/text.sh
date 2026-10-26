# Non-bats code of ours (quire#646): the check.sh scripts cannot be bats until the test driver of bats#284 (open, none exists) runs a built binary with an environment, so the avenue exhausted is a bats test, and shell builtins replace sed because the owner's rule forbids depending on it.
# Line edits for the check.sh scripts, in shell builtins and head/tail/cut (bats-lang/bats#363):
# the owner's rule is that nothing checked in depends on sed being on the machine.
# Sourced: `. "$(dirname "$0")/../text.sh"`. Each function reads stdin and writes stdout;
# `text_edit <file> <function> args...` rewrites a file in place through a new file.
# A line is read whole (no backslash or space is touched); a last line with no newline gets one.

text_line() { # <n>: line n
  head -n "$1" | tail -n 1
}
text_drop_last() { # the last line removed
  text_have=0
  while IFS= read -r text_l || [ -n "$text_l" ]; do
    if [ "$text_have" -eq 1 ]; then printf '%s\n' "$text_prev"; fi
    text_prev=$text_l; text_have=1
  done
}
text_set_line() { # <n> <text>: line n is text
  text_n=0
  while IFS= read -r text_l || [ -n "$text_l" ]; do
    text_n=$((text_n + 1))
    if [ "$text_n" -eq "$1" ]; then printf '%s\n' "$2"; else printf '%s\n' "$text_l"; fi
  done
}
text_delete_line() { # <n>: line n removed
  text_n=0
  while IFS= read -r text_l || [ -n "$text_l" ]; do
    text_n=$((text_n + 1))
    if [ "$text_n" -ne "$1" ]; then printf '%s\n' "$text_l"; fi
  done
}
text_insert_after() { # <n> <text>: text is a new line after line n
  text_n=0
  while IFS= read -r text_l || [ -n "$text_l" ]; do
    text_n=$((text_n + 1))
    printf '%s\n' "$text_l"
    if [ "$text_n" -eq "$1" ]; then printf '%s\n' "$2"; fi
  done
}
text_replace() { # <old> <new>: the first old of each line is new (literal text)
  while IFS= read -r text_l || [ -n "$text_l" ]; do
    case $text_l in
      *"$1"*) printf '%s\n' "${text_l%%"$1"*}$2${text_l#*"$1"}" ;;
      *) printf '%s\n' "$text_l" ;;
    esac
  done
}
text_replace_all() { # <old> <new>: every old is new (literal text; old is not empty)
  while IFS= read -r text_l || [ -n "$text_l" ]; do
    text_out=
    while :; do
      case $text_l in
        *"$1"*) text_out=$text_out${text_l%%"$1"*}$2; text_l=${text_l#*"$1"} ;;
        *) break ;;
      esac
    done
    printf '%s\n' "$text_out$text_l"
  done
}
text_replace_prefix() { # <old> <new>: a line that starts with old starts with new
  while IFS= read -r text_l || [ -n "$text_l" ]; do
    case $text_l in
      "$1"*) printf '%s\n' "$2${text_l#"$1"}" ;;
      *) printf '%s\n' "$text_l" ;;
    esac
  done
}
text_set_by_prefix() { # <prefix> <text>: a line that starts with prefix is text
  while IFS= read -r text_l || [ -n "$text_l" ]; do
    case $text_l in
      "$1"*) printf '%s\n' "$2" ;;
      *) printf '%s\n' "$text_l" ;;
    esac
  done
}
text_replace_line() { # <old> <new>: a line that is old is new
  while IFS= read -r text_l || [ -n "$text_l" ]; do
    if [ "$text_l" = "$1" ]; then printf '%s\n' "$2"; else printf '%s\n' "$text_l"; fi
  done
}
text_after_prefix() { # <prefix>: what follows prefix, of each line that starts with it
  while IFS= read -r text_l || [ -n "$text_l" ]; do
    case $text_l in
      "$1"*) printf '%s\n' "${text_l#"$1"}" ;;
    esac
  done
}
text_after_last() { # <text>: what follows the last text, of each line that holds it
  while IFS= read -r text_l || [ -n "$text_l" ]; do
    case $text_l in
      *"$1"*) printf '%s\n' "${text_l##*"$1"}" ;;
    esac
  done
}
text_edit() { # <file> <function> args...: the file is what the function makes of it
  text_edit_file=$1; shift
  "$@" < "$text_edit_file" > "$text_edit_file.text-edit" && mv -f "$text_edit_file.text-edit" "$text_edit_file"
}
