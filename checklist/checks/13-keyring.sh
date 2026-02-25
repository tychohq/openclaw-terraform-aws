#!/bin/bash
# Check: Credential storage — warns about tools using OS keyring/keychain
#
# Why this matters:
#   - Headless EC2 has no keychain UI → keyring auth is a hard blocker
#   - On macOS, updating CLIs (e.g. gog) can trigger 'Always Allow' keychain prompts
#   - File-based auth (.env, config files) survives updates without re-auth

_keyring_remedy="Store credentials in ~/.openclaw/.env or the tool's config file instead of OS keyring"

check_keyring() {
    section "CREDENTIAL STORAGE"

    # ── gog CLI ───────────────────────────────────────────────────────────────

    if has_cmd gog; then
        local gog_status keyring_backend
        gog_status=$(gog auth status 2>/dev/null || true)
        keyring_backend=$(echo "$gog_status" | awk -F'\t' '$1 == "keyring_backend" {print $2}')

        case "$keyring_backend" in
            file|plaintext)
                report_result "keyring.gog" "pass" "gog credential storage: $keyring_backend (file-based)"
                ;;
            keychain|system|kwallet|wincred)
                report_result "keyring.gog" "warn" \
                    "gog is using OS keyring backend: $keyring_backend" \
                    "$_keyring_remedy"
                ;;
            auto)
                if $IS_MACOS; then
                    report_result "keyring.gog" "warn" \
                        "gog keyring_backend=auto on macOS — will use Keychain, blocks headless use" \
                        "gog auth login --keyring-backend file  # or check gog docs for file-based auth"
                elif $IS_LINUX; then
                    report_result "keyring.gog" "warn" \
                        "gog keyring_backend=auto on Linux — may fail headlessly if keyring daemon absent" \
                        "$_keyring_remedy"
                else
                    report_result "keyring.gog" "pass" "gog keyring_backend=auto ($OS_TYPE)"
                fi
                ;;
            "")
                report_result "keyring.gog" "skip" "gog keyring_backend not reported (not authenticated?)"
                ;;
            *)
                report_result "keyring.gog" "pass" "gog credential storage: $keyring_backend"
                ;;
        esac
    else
        report_result "keyring.gog" "skip" "gog not installed"
    fi

    # ── gh CLI ────────────────────────────────────────────────────────────────

    if has_cmd gh; then
        local hosts_file="$HOME/.config/gh/hosts.yml"

        if [ ! -f "$hosts_file" ]; then
            report_result "keyring.gh" "skip" "gh hosts.yml not found (not authenticated?)"
        elif grep -q 'oauth_token:' "$hosts_file" 2>/dev/null; then
            report_result "keyring.gh" "pass" "gh token stored in config file (file-based)"
        else
            # Token absent from file → gh is using OS keychain
            if $IS_MACOS; then
                report_result "keyring.gh" "warn" \
                    "gh token is stored in macOS Keychain (not in config file)" \
                    "gh auth login --with-token < tokenfile  # uses GITHUB_TOKEN env var or stdin"
            elif $IS_LINUX; then
                report_result "keyring.gh" "warn" \
                    "gh token not found in config file — may be using OS keyring" \
                    "Set GITHUB_TOKEN in ~/.openclaw/.env for headless operation"
            else
                report_result "keyring.gh" "pass" "gh config file present (token location unclear)"
            fi
        fi
    else
        report_result "keyring.gh" "skip" "gh not installed"
    fi

    # ── Linux: gnome-keyring / libsecret (headless danger) ───────────────────

    if $IS_LINUX; then
        local keyring_pkgs=()
        has_cmd gnome-keyring-daemon && keyring_pkgs+=("gnome-keyring")
        has_cmd secret-tool           && keyring_pkgs+=("libsecret/secret-tool")

        if [ "${#keyring_pkgs[@]}" -gt 0 ]; then
            report_result "keyring.linux_keyring" "warn" \
                "OS keyring daemon detected: ${keyring_pkgs[*]} — may block headless credential access" \
                "Use file-based auth. Uninstall if not needed: dnf remove gnome-keyring libsecret"
        else
            report_result "keyring.linux_keyring" "pass" "No OS keyring daemon installed (good for headless EC2)"
        fi
    fi

    # ── General: check for GITHUB_TOKEN / GOG_TOKEN env override ─────────────
    # Token env vars bypass keyring entirely — flag if set (good practice)

    local env_file="$HOME/.openclaw/.env"
    local file_creds=()

    [ -n "${GITHUB_TOKEN:-}" ] && file_creds+=("GITHUB_TOKEN (env)")
    [ -f "$env_file" ] && grep -q '^GITHUB_TOKEN=.' "$env_file" 2>/dev/null && \
        file_creds+=("GITHUB_TOKEN (.env)")

    if [ "${#file_creds[@]}" -gt 0 ]; then
        report_result "keyring.env_creds" "pass" "File-based credentials found: ${file_creds[*]}"
    fi
}
