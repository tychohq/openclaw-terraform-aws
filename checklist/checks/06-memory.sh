#!/bin/bash
# Check: Memory search via openclaw memory status

check_memory() {
    section "MEMORY & WORKSPACE"

    if ! has_cmd openclaw; then
        report_result "memory.status" "fail" "openclaw CLI not found" \
            "Install openclaw to check memory status"
        return
    fi

    local memory_output
    memory_output=$(safe_timeout 15 openclaw memory status 2>&1)

    if [ -z "$memory_output" ]; then
        report_result "memory.status" "fail" \
            "openclaw memory status returned no output" \
            "openclaw memory status  # check manually"
        return
    fi

    # Provider and model (informational)
    local provider model
    provider=$(echo "$memory_output" | awk '/^Provider:/{print $2}')
    model=$(echo "$memory_output" | awk '/^Model:/{print $2}')
    report_result "memory.provider" "pass" "Memory provider: ${provider:-unknown} (${model:-unknown})"

    # Indexed files and chunks: "Indexed: 300/1663 files · 2760 chunks"
    local indexed_line indexed_files total_files chunks
    indexed_line=$(echo "$memory_output" | grep '^Indexed:')
    indexed_files=$(echo "$indexed_line" | grep -oE '[0-9]+/' | head -1 | tr -d '/')
    total_files=$(echo "$indexed_line" | grep -oE '/[0-9]+' | head -1 | tr -d '/')
    chunks=$(echo "$indexed_line" | grep -oE '[0-9]+ chunks' | awk '{print $1}')

    if [ -n "$indexed_files" ]; then
        report_result "memory.indexed" "pass" \
            "Indexed: ${indexed_files}/${total_files:-?} files · ${chunks:-?} chunks"
    else
        report_result "memory.indexed" "warn" \
            "Could not parse indexed file count" \
            "openclaw memory status  # check manually"
    fi

    # Dirty flag: warn if index needs reindexing
    local dirty
    dirty=$(echo "$memory_output" | awk '/^Dirty:/{print $2}')
    if [ "$dirty" = "yes" ]; then
        report_result "memory.dirty" "warn" "Memory index is dirty — needs reindex" \
            "openclaw memory reindex"
    else
        report_result "memory.dirty" "pass" "Memory index is clean"
    fi

    # Vector search readiness
    if echo "$memory_output" | grep -q '^Vector: ready'; then
        local dims
        dims=$(echo "$memory_output" | awk '/^Vector dims:/{print $3}')
        report_result "memory.vector" "pass" \
            "Vector search: ready${dims:+ (dims: $dims)}"
    else
        local vector_line
        vector_line=$(echo "$memory_output" | grep '^Vector:')
        report_result "memory.vector" "warn" \
            "Vector search not ready: ${vector_line:-no output}" \
            "openclaw memory reindex  # or check embedding provider config"
    fi

    # Full-text search readiness
    if echo "$memory_output" | grep -q '^FTS: ready'; then
        report_result "memory.fts" "pass" "Full-text search: ready"
    else
        local fts_line
        fts_line=$(echo "$memory_output" | grep '^FTS:')
        report_result "memory.fts" "warn" \
            "Full-text search not ready: ${fts_line:-no output}"
    fi

    # Embedding cache (informational)
    local cache_entries
    cache_entries=$(echo "$memory_output" | \
        grep '^Embedding cache:' | grep -oE '[0-9]+ entries' | awk '{print $1}')
    [ -n "$cache_entries" ] && \
        report_result "memory.cache" "pass" "Embedding cache: $cache_entries entries"
}
