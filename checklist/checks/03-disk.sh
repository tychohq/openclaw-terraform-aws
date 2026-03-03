#!/bin/bash
# Check: Disk space, RAM usage, log sizes

check_disk() {
    section "DISK & MEMORY"

    # ── Root volume free space (df works on both platforms) ───────────────────

    local use_pct avail free_pct
    use_pct=$(df / | tail -1 | awk '{gsub(/%/,""); print $5}')
    avail=$(df -h / | tail -1 | awk '{print $4}')
    free_pct=$((100 - use_pct))

    if [ "$free_pct" -gt 20 ]; then
        report_result "disk.root" "pass" "Root volume: ${free_pct}% free ($avail available)"
    elif [ "$free_pct" -gt 10 ]; then
        report_result "disk.root" "warn" "Root volume low: ${free_pct}% free ($avail available)" \
            "journalctl --vacuum-time=7d  # or: docker system prune -f"
    else
        report_result "disk.root" "fail" "Root volume critically low: ${free_pct}% free ($avail available)" \
            "journalctl --vacuum-time=3d && find /tmp -type f -mtime +1 -delete"
    fi

    # ── RAM usage (OS-aware) ──────────────────────────────────────────────────

    if $IS_LINUX && has_cmd free; then
        local total used use_mem_pct
        total=$(free | awk '/^Mem:/{print $2}')
        used=$(free | awk '/^Mem:/{print $3}')
        use_mem_pct=$((used * 100 / total))

        if [ "$use_mem_pct" -lt 90 ]; then
            report_result "disk.memory" "pass" "RAM usage: ${use_mem_pct}%"
        else
            report_result "disk.memory" "warn" "RAM usage high: ${use_mem_pct}%" \
                "ps aux --sort=-%mem | head -20  # find memory hogs"
        fi

    elif $IS_MACOS; then
        # macOS: use memory_pressure which accounts for inactive/purgeable/compressed
        # pages that macOS can reclaim (raw vm_stat "free" pages is misleading)
        local free_pct_line use_mem_pct
        free_pct_line=$(memory_pressure 2>/dev/null | grep 'System-wide memory free percentage:')

        if [ -n "$free_pct_line" ]; then
            local free_mem_pct
            free_mem_pct=$(echo "$free_pct_line" | grep -oE '[0-9]+')
            use_mem_pct=$((100 - free_mem_pct))

            if [ "$use_mem_pct" -lt 90 ]; then
                report_result "disk.memory" "pass" "RAM usage: ~${use_mem_pct}% (${free_mem_pct}% free)"
            else
                report_result "disk.memory" "warn" "RAM usage high: ~${use_mem_pct}%" \
                    "ps aux -m | head -20  # find memory hogs"
            fi
        else
            report_result "disk.memory" "skip" "Could not compute RAM usage on macOS"
        fi

    else
        report_result "disk.memory" "skip" "RAM check not supported on $OS_TYPE"
    fi

    # ── Log sizes ─────────────────────────────────────────────────────────────

    if $IS_LINUX; then
        # EC2 install log
        if [ -f /var/log/openclaw-install.log ]; then
            local log_size
            log_size=$(du -sh /var/log/openclaw-install.log 2>/dev/null | cut -f1)
            report_result "disk.install_log" "pass" "Install log: $log_size"
        else
            report_result "disk.install_log" "skip" "Install log not present"
        fi

        # systemd journal size
        if has_cmd journalctl; then
            local journal_size
            journal_size=$(journalctl --disk-usage 2>/dev/null \
                | grep -oE '[0-9.]+ [A-Za-z]+' | head -1 || echo "unknown")
            report_result "disk.journal" "pass" "systemd journal: $journal_size"
        fi

    elif $IS_MACOS; then
        # macOS gateway log files
        local log_dir="$HOME/.openclaw/logs"
        if [ -d "$log_dir" ]; then
            local log_size
            log_size=$(du -sh "$log_dir" 2>/dev/null | cut -f1)
            report_result "disk.logs" "pass" "Gateway logs ($log_dir): $log_size"
        else
            report_result "disk.logs" "skip" "No gateway log directory found ($log_dir)"
        fi
    fi
}
