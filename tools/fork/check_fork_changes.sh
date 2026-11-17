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

# Lists fork commits (in <upstream-ref>..HEAD, merges excluded) whose title is missing from FORK_CHANGES.md,
# and exits 1 when any is missing. Titles are the key because rebasing onto a new upstream changes the hashes.
#
# Usage: tools/fork/check_fork_changes.sh [upstream-ref]    default: upstream/master (run `git fetch upstream` first)

set -euo pipefail

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
UPSTREAM_REF="${1:-upstream/master}"
DOC="${ROOT}/FORK_CHANGES.md"

missing=0
total=0
while IFS= read -r line; do
    total=$((total + 1))
    title="${line#* }"
    if ! grep -qF -- "${title}" "${DOC}"; then
        echo "missing from FORK_CHANGES.md: ${line}"
        missing=$((missing + 1))
    fi
done < <(git -C "${ROOT}" log --no-merges --format='%h %s' "${UPSTREAM_REF}..HEAD")

echo "fork commits: ${total}, missing: ${missing}"
if [[ "${missing}" -gt 0 ]]; then
    exit 1
fi
