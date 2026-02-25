#!/bin/bash
# Check: Cron scheduler — job files and gateway prerequisite

check_cron() {
    section "CRON SCHEDULER"

    # Prerequisite: gateway must be running (OS-aware via lib.sh helper)
    if ! gateway_is_running; then
        local start_cmd="openclaw gateway start"
        $IS_LINUX && start_cmd="systemctl --user start openclaw-gateway"
        report_result "cron.gateway" "warn" \
            "Gateway is not running — skipping cron checks" \
            "$start_cmd"
        return
    fi

    report_result "cron.gateway" "pass" "Gateway prerequisite: running"

    # Check cron job files
    local cron_dir="$HOME/.openclaw/workspace/cron-jobs"

    if [ ! -d "$cron_dir" ]; then
        report_result "cron.files" "skip" "No cron-jobs directory found ($cron_dir)" \
            "Ask OpenClaw to create a cron job — it will create the directory"
        return
    fi

    local cron_count
    cron_count=$(find "$cron_dir" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$cron_count" -gt 0 ]; then
        report_result "cron.files" "pass" "$cron_count cron job file(s) in $cron_dir"

        # List each job file
        while IFS= read -r job_file; do
            local job_name
            job_name=$(basename "$job_file" .json)
            report_result "cron.job.$job_name" "pass" "Cron job defined: $job_name"
        done < <(find "$cron_dir" -maxdepth 1 -name "*.json" 2>/dev/null | sort)
    else
        report_result "cron.files" "skip" "No cron job files in $cron_dir" \
            "Ask OpenClaw to register a cron job"
    fi
}
