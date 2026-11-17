#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# Runs the fork's security gate: the 12 GitLab SAST semgrep rules that must report zero findings
# (see FORK_CHANGES.md). Prints one "<rule>\t<path>:<line>" per finding and "TOTAL <n>"; exits 1 when n > 0.
#
# Usage: tools/fork/semgrep_gate.sh [path ...]    paths relative to the repo root; default: the whole repo
# Needs: semgrep (pip install semgrep), curl, tar, python3.
# The rules are downloaded once, pinned by commit, into ${DORIS_FORK_SEMGREP_CACHE:-~/.cache/doris-fork-semgrep}.

set -euo pipefail

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
CACHE="${DORIS_FORK_SEMGREP_CACHE:-${HOME}/.cache/doris-fork-semgrep}"
SEMGREP="${SEMGREP:-semgrep}"
ARCHIVE_URL="https://gitlab.com/gitlab-org/security-products/sast-rules/-/archive"
# Last commit before 22fe8755 "Remove poor java rules": still ships PATH_TRAVERSAL_IN/OUT and the other java rules.
OLD_RULES_SHA="390440abc3d458ad6dea6586c19ca29d14201699"
# The old URLCONNECTION_SSRF_FD-1 rule no longer parses in current semgrep; this version keeps the same id.
SSRF_RULES_SHA="83144bd2ec7d3200cda96347fa923f81c8ad8413"

# fetch <sha> <path-in-repo>: download one directory of sast-rules at <sha> into the cache.
fetch() {
    local sha="$1" path="$2" dest="${CACHE}/$1/$2" tmp
    if [[ -d "${dest}" ]]; then
        return
    fi
    tmp="$(mktemp -d)"
    curl -sSfL "${ARCHIVE_URL}/${sha}/sast-rules.tar.gz?path=${path}" | tar xz -C "${tmp}"
    mkdir -p "$(dirname "${dest}")"
    mv "${tmp}"/sast-rules-*/"${path}" "${dest}"
    rm -rf "${tmp}"
}

fetch "${OLD_RULES_SHA}" dist
fetch "${SSRF_RULES_SHA}" java/ssrf

OUT="$(mktemp)"
trap 'rm -f "${OUT}"' EXIT

cd "${ROOT}"
if [[ $# -eq 0 ]]; then
    set -- .
fi
# The excludes mirror GitLab SAST's default SAST_EXCLUDED_PATHS (spec, test, tests, tmp) plus build outputs.
# semgrep exits non-zero when the one unparsable old SSRF rule is reported, so the JSON is checked instead.
"${SEMGREP}" scan --metrics=off --disable-version-check -q \
    --config "${CACHE}/${OLD_RULES_SHA}/dist/find_sec_bugs.yml" \
    --config "${CACHE}/${OLD_RULES_SHA}/dist/gosec.yml" \
    --config "${CACHE}/${OLD_RULES_SHA}/dist/bandit.yml" \
    --config "${CACHE}/${OLD_RULES_SHA}/dist/flawfinder.yml" \
    --config "${CACHE}/${SSRF_RULES_SHA}/java/ssrf/rule-SSRF.yml" \
    --exclude spec --exclude test --exclude tests --exclude tmp \
    --exclude thirdparty --exclude output --exclude node_modules \
    --timeout 30 --max-target-bytes 2000000 --json -o "${OUT}" "$@" >/dev/null 2>&1 || true

python3 -I - "${OUT}" <<'EOF'
import json
import sys

GATE = {
    "find_sec_bugs.PATH_TRAVERSAL_IN-1": "PATH_TRAVERSAL_IN",
    "find_sec_bugs.PATH_TRAVERSAL_OUT-1.PATH_TRAVERSAL_OUT-1": "PATH_TRAVERSAL_OUT",
    "find_sec_bugs.SQL_INJECTION_SPRING_JDBC-1.SQL_INJECTION_JPA-1.SQL_INJECTION_JDO-1.SQL_INJECTION_JDBC-1."
    "SQL_NONCONSTANT_STRING_PASSED_TO_EXECUTE-1.SQL_INJECTION-1.SQL_INJECTION_HIBERNATE-1.SQL_INJECTION_VERTX-1."
    "SQL_PREPARED_STATEMENT_GENERATED_FROM_NONCONSTANT_STRING-1": "SQL_INJECTION",
    "find_sec_bugs.URLCONNECTION_SSRF_FD-1": "SSRF",
    "find_sec_bugs.HARD_CODE_PASSWORD-1": "HARD_CODE_PASSWORD",
    "gosec.G101-1": "G101",
    "bandit.B602": "B602",
    "find_sec_bugs.IMPROPER_UNICODE-1": "IMPROPER_UNICODE",
    "find_sec_bugs.CRLF_INJECTION_LOGS-1": "CRLF_INJECTION_LOGS",
    "flawfinder.strcpy-1": "strcpy",
    "flawfinder.strcat-1": "strcat",
    "find_sec_bugs.UNVALIDATED_REDIRECT-1.URL_REWRITING-1": "UNVALIDATED_REDIRECT",
}

report = json.load(open(sys.argv[1]))
broken = [e for e in report.get("errors", []) if e.get("level") == "error" and "SSRF" not in str(e.get("message"))]
if broken:
    sys.exit("semgrep failed: " + "; ".join(str(e.get("message"))[:200] for e in broken[:5]))
hits = set()
for result in report["results"]:
    rule = GATE.get(result["extra"].get("metadata", {}).get("primary_identifier"))
    if result["check_id"].endswith("java_ssrf_rule-SSRF"):
        # The newer SSRF rule carries no primary_identifier; sast-rules maps it to URLCONNECTION_SSRF_FD-1.
        rule = "SSRF"
    if rule is not None:
        hits.add((rule, result["path"], result["start"]["line"]))
for rule, path, line in sorted(hits):
    print(f"{rule}\t{path}:{line}")
print("TOTAL", len(hits))
sys.exit(1 if hits else 0)
EOF
