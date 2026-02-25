#!/bin/bash
# Check: Disk space, RAM usage, log sizes

check_disk() {
    section "DISK & MEMORY"

    # Root volume free space
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

    # RAM usage
    if has_cmd free; then
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
    else
        report_result "disk.memory" "skip" "free command not available"
    fi

    # Install log size
    if [ -f /var/log/openclaw-install.log ]; then
        local log_size
        log_size=$(du -sh /var/log/openclaw-install.log 2>/dev/null | cut -f1)
        report_result "disk.install_log" "pass" "Install log: $log_size"
    else
        report_result "disk.install_log" "skip" "Install log not present (normal if not on EC2)"
    fi

    # Journal disk usage
    if has_cmd journalctl; then
        local journal_size
        journal_size=$(journalctl --disk-usage 2>/dev/null \
            | grep -oE '[0-9.]+ [A-Za-z]+' | head -1 || echo "unknown")
        report_result "disk.journal" "pass" "systemd journal: $journal_size" \
            # no remediation — informational
    else
        report_result "disk.journal" "skip" "journalctl not available"
    fi
}
