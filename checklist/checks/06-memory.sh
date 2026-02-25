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

    # Per-source breakdown from "By source:" section
    # Lines: "  memory · 291/292 files · 1938 chunks"
    local in_by_source=false found_sources=false
    while IFS= read -r line; do
        if echo "$line" | grep -q '^By source:'; then
            in_by_source=true
            continue
        fi
        if $in_by_source; then
            # Indented source lines start with spaces
            if echo "$line" | grep -qE '^  [^ ]'; then
                found_sources=true
                local src_name src_indexed src_total src_chunks
                src_name=$(echo "$line" | awk -F' · ' '{gsub(/^[[:space:]]+/,"",$1); print $1}')
                src_indexed=$(echo "$line" | grep -oE '[0-9]+/' | head -1 | tr -d '/')
                src_total=$(echo "$line" | grep -oE '/[0-9]+' | head -1 | tr -d '/')
                src_chunks=$(echo "$line" | grep -oE '[0-9]+ chunks' | awk '{print $1}')

                if [ -n "$src_indexed" ] && [ -n "$src_total" ] && [ "$src_total" -gt 0 ]; then
                    local pct src_status
                    pct=$((src_indexed * 100 / src_total))
                    if   [ "$pct" -lt 10 ]; then src_status="fail"
                    elif [ "$pct" -lt 50 ]; then src_status="warn"
                    else                          src_status="pass"
                    fi
                    local safe_src
                    safe_src=$(echo "$src_name" | tr -cs 'a-zA-Z0-9' '_' | sed 's/_$//')
                    report_result "memory.source.$safe_src" "$src_status" \
                        "${src_name} files: ${src_indexed}/${src_total} indexed (${pct}%)${src_chunks:+ · $src_chunks chunks}"
                fi
            else
                # Non-indented line ends the section
                in_by_source=false
            fi
        fi
    done <<< "$memory_output"

    if ! $found_sources; then
        # Fallback: show total if per-source parsing failed
        local indexed_line indexed_files total_files chunks
        indexed_line=$(echo "$memory_output" | grep '^Indexed:')
        indexed_files=$(echo "$indexed_line" | grep -oE '[0-9]+/' | head -1 | tr -d '/')
        total_files=$(echo "$indexed_line" | grep -oE '/[0-9]+' | head -1 | tr -d '/')
        chunks=$(echo "$indexed_line" | grep -oE '[0-9]+ chunks' | awk '{print $1}')
        report_result "memory.indexed" "pass" \
            "Indexed: ${indexed_files:-?}/${total_files:-?} files · ${chunks:-?} chunks"
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
