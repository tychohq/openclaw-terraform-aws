#!/bin/bash
# Check: Workspace structure, MEMORY.md, git repo, embeddings

check_memory() {
    section "MEMORY & WORKSPACE"

    local workspace="$HOME/.openclaw/workspace"
    local openclaw_dir="$HOME/.openclaw"

    # Workspace directory structure
    local dirs_ok=true
    for dir in memory docs tools; do
        if [ ! -d "$workspace/$dir" ]; then
            dirs_ok=false
            break
        fi
    done

    if $dirs_ok; then
        report_result "memory.dirs" "pass" "Workspace directories exist (memory, docs, tools)"
    else
        report_result "memory.dirs" "fail" "Workspace directories incomplete" \
            "mkdir -p ~/.openclaw/workspace/{memory,docs,tools}"
    fi

    # MEMORY.md exists (check both common locations)
    if [ -f "$workspace/memory/MEMORY.md" ] || [ -f "$workspace/MEMORY.md" ]; then
        report_result "memory.file" "pass" "MEMORY.md exists"
    else
        report_result "memory.file" "warn" "MEMORY.md not found" \
            "touch ~/.openclaw/workspace/memory/MEMORY.md"
    fi

    # .openclaw is a git repo
    if [ -d "$openclaw_dir/.git" ]; then
        local commit_count
        commit_count=$(git -C "$openclaw_dir" rev-list --count HEAD 2>/dev/null || echo "0")
        report_result "memory.git" "pass" ".openclaw is a git repo ($commit_count commits)"
    else
        report_result "memory.git" "warn" ".openclaw is not a git repository" \
            "cd ~/.openclaw && git init && git add -A && git commit -m 'Initial workspace'"
    fi

    # Embedding index (optional — built on first use)
    local embeddings_found=false
    local embed_path_found=""
    for embed_path in \
        "$workspace/.embeddings" \
        "$workspace/embeddings" \
        "$openclaw_dir/.embeddings" \
        "$workspace/memory/.embeddings"; do
        if [ -d "$embed_path" ]; then
            embeddings_found=true
            embed_path_found="$embed_path"
            break
        fi
    done

    if $embeddings_found; then
        report_result "memory.embeddings" "pass" "Embedding index found at $embed_path_found"
    else
        report_result "memory.embeddings" "skip" "No embedding index (built automatically on first use)"
    fi
}
