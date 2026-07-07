#!/usr/bin/env bash
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/tags.sh"
source "$HERE/lib/recipe.sh"
source "$HERE/lib/lint.sh"
source "$HERE/lib/assert.sh"
source "$HERE/lib/drive_scale.sh" 2>/dev/null || true   # added in Task 11

usage() { echo "usage: run.sh lint <recipe> | run.sh test --env <kind|existing|ocp> --modelserver <sim|vllm> <recipe>" >&2; exit 2; }

cmd="${1:-}"; shift || true
case "$cmd" in
  lint)
    [[ $# -eq 1 ]] || usage
    lint_recipe "$1"
    ;;
  test)
    ENV=""; MS=""; RECIPE=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --env) ENV="$2"; shift 2 ;;
        --modelserver) MS="$2"; shift 2 ;;
        -*) echo "unknown flag: $1" >&2; usage ;;
        *) RECIPE="$1"; shift ;;
      esac
    done
    [[ -n "$ENV" && -n "$MS" && -n "$RECIPE" ]] || usage
    case "$ENV" in kind|existing|ocp) ;; *) echo "bad --env: $ENV" >&2; usage ;; esac
    case "$MS" in sim|vllm) ;; *) echo "bad --modelserver: $MS" >&2; usage ;; esac
    if [[ "$ENV" == "kind" && "$MS" == "vllm" ]]; then
      echo "error: --env kind --modelserver vllm is unsupported (no GPU in Kind on a laptop)." >&2
      exit 2
    fi
    echo "==> lint"
    lint_recipe "$RECIPE"
    if [[ "${RUNNER_LINT_ONLY:-0}" == "1" ]]; then echo "(lint-only mode)"; exit 0; fi
    # Full execution wired in Tasks 8-11:
    source "$HERE/profiles/$ENV.sh"
    run_env_provision "$MS" "$RECIPE"          # Task 8/9/10
    runner_exec_steps "$RECIPE" "$MS"          # Task 11
    runner_drive_and_assert "$RECIPE" "$MS"    # Task 11
    ;;
  ""|-h|--help) usage ;;
  *) echo "unknown command: $cmd" >&2; usage ;;
esac
