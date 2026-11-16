# Replaces SWE-agent v1.1.0's tools/edit_anthropic/install.sh, which runs a bare `pip install`
# and crashes setup (exit 127) in task images that have no `pip` on PATH. Installs into the same
# python3 the editor tool runs with, bootstrapping pip first if needed. Never fails setup: if pip
# cannot be had, only the editor's large-file outline (tree-sitter) is unavailable.
PY=$(command -v python3 || command -v python)
$PY -m pip --version >/dev/null 2>&1 || $PY -m ensurepip --upgrade >/dev/null 2>&1 || true
$PY -m pip --version >/dev/null 2>&1 || { curl -sS https://bootstrap.pypa.io/get-pip.py | $PY - >/dev/null 2>&1 || true; }
$PY -m pip install -q 'tree-sitter==0.21.3' 'tree-sitter-languages' || true
true
