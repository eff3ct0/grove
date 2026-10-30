load helpers

@test "clone puts the repo at <root>/<owner>/<repo> with GitHub's casing and prints the path" {
  remote_repo Acme/Widget
  run "$grove" clone acme/widget
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "$GROVE_ROOT/Acme/Widget" ]
  [ -f "$GROVE_ROOT/Acme/Widget/README.md" ]
}

@test "clone accepts GitHub URLs" {
  remote_repo acme/widget
  run "$grove" clone https://github.com/acme/widget.git
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "$GROVE_ROOT/acme/widget" ]
}

@test "clone of a fork adds upstream" {
  remote_repo upstream-org/tool
  remote_repo me/tool upstream-org/tool
  "$grove" clone me/tool
  [ "$(git -C "$GROVE_ROOT/me/tool" config remote.upstream.url)" = https://github.com/upstream-org/tool.git ]
}

@test "clone passes flags after -- to git clone" {
  remote_repo acme/widget
  "$grove" clone acme/widget -- --depth 1
  [ "$(git -C "$GROVE_ROOT/acme/widget" rev-parse --is-shallow-repository)" = true ]
}

@test "clone of an existing clone only prints the path" {
  remote_repo acme/widget
  "$grove" clone acme/widget
  echo local >"$GROVE_ROOT/acme/widget/untracked"
  run "$grove" clone acme/widget
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "$GROVE_ROOT/acme/widget" ]
  [ -f "$GROVE_ROOT/acme/widget/untracked" ]
}

@test "clone of a missing repo fails" {
  run "$grove" clone acme/nope
  [ "$status" -ne 0 ]
  [ ! -e "$GROVE_ROOT/acme/nope" ]
}
