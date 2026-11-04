# bash completion for claude-ask; `just install` links it into
# ${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-~/.local/share}/bash-completion}/completions
# as claude-ask, where bash-completion loads it on first use (or source it)

_claude_ask_options="-i --interactive -r --resume --resume= -e --effort --effort=
  -m --model --model= -y --yank -Y --yank-code --yank-code= --split --split= --popup
  --theme --theme= --pager --pager= --no-pager --demo-themes --demo-output --no-stream
  --save-raw --history --session --session= --debug-log --debug-log= --version -h --help"

# Saved session names (for --session and --resume=)
_claude_ask_sessions() {
  local dir="${SESSION_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-ask/sessions}" f name
  for f in "$dir"/*.json; do
    [[ -e "$f" ]] || continue
    name="${f##*/}"
    printf '%s\n' "${name%.json}"
  done
}

# _claude_ask_reply WORD CANDIDATE...: COMPREPLY from the candidates that
# start with WORD
_claude_ask_reply() {
  local word="$1" c
  shift
  COMPREPLY=()
  for c in "$@"; do
    if [[ "$c" == "$word"* ]]; then COMPREPLY+=("$c"); fi
  done
}

_claude_ask() {
  local cur="${COMP_WORDS[COMP_CWORD]}" prev="" opt=""
  local -a names
  if ((COMP_CWORD > 0)); then prev="${COMP_WORDS[COMP_CWORD - 1]}"; fi

  # bash splits --opt=value at the = (COMP_WORDBREAKS): "--opt" "=" "value"
  if [[ "$cur" == "=" ]]; then
    opt="$prev"
    cur=""
  elif [[ "$prev" == "=" ]] && ((COMP_CWORD > 1)); then
    opt="${COMP_WORDS[COMP_CWORD - 2]}"
  elif [[ "$cur" == --*=* ]]; then
    # COMP_WORDBREAKS without =
    opt="${cur%%=*}"
    cur="${cur#*=}"
  fi
  if [[ -n "$opt" ]]; then
    case "$opt" in
      --resume | --session)
        mapfile -t names < <(_claude_ask_sessions)
        _claude_ask_reply "$cur" "${names[@]}"
        ;;
      --split) _claude_ask_reply "$cur" h v auto ;;
      --effort) _claude_ask_reply "$cur" low medium high xhigh max ;;
      --model) _claude_ask_reply "$cur" opus sonnet haiku fable ;;
      --theme) _claude_ask_reply "$cur" minimal bubbles powerline ;;
      --pager) mapfile -t COMPREPLY < <(compgen -c -- "$cur") ;;
      --debug-log) mapfile -t COMPREPLY < <(compgen -f -- "$cur") ;;
      *) COMPREPLY=() ;;
    esac
    return 0
  fi

  case "$prev" in
    -e | --effort)
      _claude_ask_reply "$cur" low medium high xhigh max
      return 0
      ;;
    -m | --model)
      _claude_ask_reply "$cur" opus sonnet haiku fable
      return 0
      ;;
    --theme)
      _claude_ask_reply "$cur" minimal bubbles powerline
      return 0
      ;;
    --pager)
      mapfile -t COMPREPLY < <(compgen -c -- "$cur")
      return 0
      ;;
    --session)
      if [[ "$cur" != -* ]]; then
        mapfile -t names < <(_claude_ask_sessions)
        _claude_ask_reply "$cur" "${names[@]}"
        return 0
      fi
      ;;
  esac

  if [[ "$cur" == -* ]]; then
    # shellcheck disable=SC2086 # the option list is split into words
    _claude_ask_reply "$cur" $_claude_ask_options
    # An option ending in = takes its value with no space after it
    if [[ ${#COMPREPLY[@]} -eq 1 && "${COMPREPLY[0]}" == *= ]]; then
      compopt -o nospace 2> /dev/null || true
    fi
  else
    # The question
    COMPREPLY=()
  fi
  return 0
}

complete -F _claude_ask claude-ask
