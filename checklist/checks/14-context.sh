#!/bin/bash
# Check: Context and session management settings (informational only)

# Return the context window size string for a known model, empty string if unknown.
_model_ctx_window() {
    local short="${1##*/}"   # strip "provider/" prefix
    case "$short" in
        claude-opus-4-6)                         echo "200k" ;;
        claude-sonnet-4-5|claude-sonnet-4-6)     echo "200k" ;;
        claude-haiku-4-5*)                        echo "200k" ;;
        claude-3-5-sonnet*|claude-3-opus*)        echo "200k" ;;
        gpt-5.3-codex)                            echo "200k" ;;
        gpt-4o*)                                  echo "128k" ;;
        gpt-4-turbo*)                             echo "128k" ;;
        *)                                        echo ""     ;;
    esac
}

# Format an integer with comma thousands separators: 80000 → 80,000
_comma_number() {
    echo "$1" | rev | sed 's/[0-9]\{3\}/&,/g' | rev | sed 's/^,//'
}

check_context() {
    section "CONTEXT & SESSION SETTINGS"

    if ! has_cmd openclaw; then
        info_msg "openclaw CLI not found — cannot check context settings"
        return
    fi

    if ! has_cmd jq; then
        info_msg "jq not found — cannot parse context settings (brew install jq)"
        return
    fi

    # ── Model ─────────────────────────────────────────────────────────────────
    local model_json
    model_json=$(safe_timeout 5 openclaw config get agents.defaults.model 2>/dev/null)

    if [ -n "$model_json" ]; then
        local primary
        primary=$(echo "$model_json" | jq -r '.primary // empty' 2>/dev/null)

        if [ -n "$primary" ]; then
            local short_primary ctx
            short_primary="${primary##*/}"
            ctx=$(_model_ctx_window "$primary")
            if [ -n "$ctx" ]; then
                info_msg "Model: $short_primary ($ctx context window)"
            else
                info_msg "Model: $short_primary"
            fi
        fi

        # Fallback models
        local fallbacks
        fallbacks=$(echo "$model_json" | \
            jq -r '.fallbacks // [] | .[]' 2>/dev/null | \
            sed 's|.*/||' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
        [ -n "$fallbacks" ] && info_msg "Fallback models: $fallbacks"
    fi

    # ── Context pruning ────────────────────────────────────────────────────────
    local pruning_json
    pruning_json=$(safe_timeout 5 openclaw config get agents.defaults.contextPruning 2>/dev/null)

    if [ -n "$pruning_json" ]; then
        local pruning_mode pruning_ttl
        pruning_mode=$(echo "$pruning_json" | jq -r '.mode // "unknown"' 2>/dev/null)
        pruning_ttl=$(echo "$pruning_json"  | jq -r '.ttl  // empty'    2>/dev/null)
        if [ -n "$pruning_ttl" ]; then
            info_msg "Context pruning: $pruning_mode (TTL: $pruning_ttl)"
        else
            info_msg "Context pruning: $pruning_mode"
        fi
    fi

    # ── Compaction ────────────────────────────────────────────────────────────
    local compaction_json
    compaction_json=$(safe_timeout 5 openclaw config get agents.defaults.compaction 2>/dev/null)

    if [ -n "$compaction_json" ]; then
        local compaction_mode reserve_floor
        compaction_mode=$(echo "$compaction_json" | jq -r '.mode               // "unknown"' 2>/dev/null)
        reserve_floor=$(echo "$compaction_json"   | jq -r '.reserveTokensFloor // empty'     2>/dev/null)

        info_msg "Compaction: $compaction_mode mode"

        if [ -n "$reserve_floor" ]; then
            info_msg "Reserve tokens floor: $(_comma_number "$reserve_floor")"
        fi
    fi
}
