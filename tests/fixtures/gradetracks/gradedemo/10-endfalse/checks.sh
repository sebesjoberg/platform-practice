check_code "ok" true "never"
[[ -n "${UNSET_VAR_X:-}" ]] && check_code "never" true "never"
