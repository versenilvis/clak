#!/usr/bin/env bash
set -euo pipefail

# configuration and defaults
REPO="versenilvis/clak"
API_URL="${CLAK_API_URL:-https://api.github.com}"
RELEASE_TAG="${CLAK_RELEASE_TAG:-}"
DRY_RUN=0
DEMO_UINPUT=0
TARGET_MODE="user"

# parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --dry-run|--simulate|-d)
            DRY_RUN=1
            ;;
        --demo-uinput)
            DEMO_UINPUT=1
            ;;
        --system|-s)
            TARGET_MODE="system"
            ;;
        --user|-u)
            TARGET_MODE="user"
            ;;
        --tag=*)
            RELEASE_TAG="${arg#*=}"
            ;;
        --help|-h)
            echo "Cách dùng: curl -fsSL https://raw.githubusercontent.com/versenilvis/clak/main/scripts/install.sh | bash [options]"
            echo "Hoặc: bash scripts/install.sh [options]"
            echo ""
            echo "Tùy chọn:"
            echo "  -d, --dry-run, --simulate  Chạy giả lập kiểm tra giao diện và quy trình (không sửa hệ thống)"
            echo "  -u, --user                 Cài vào thư mục người dùng (~/.local) [mặc định, không cần sudo]"
            echo "  -s, --system               Cài vào toàn hệ thống (/usr) [sẽ hỏi sudo khi chép file]"
            echo "      --tag=<phiên bản>      Chỉ định phiên bản release cần cài (ví dụ: v0.1.0)"
            echo "  -h, --help                 Hiển thị trợ giúp này"
            exit 0
            ;;
    esac
done

# visual palette and terminal formatting
c_reset="\033[0m"
c_dim="\033[38;5;244m"
c_bold="\033[1m"
c_cyan="\033[1;36m"
c_blue="\033[1;34m"
c_green="\033[1;32m"
c_yellow="\033[1;33m"
c_purple="\033[1;35m"
c_red="\033[1;31m"
c_gray="\033[38;5;240m"
c_accent="\033[38;5;75m"

sep="${c_gray}│${c_reset}"
lbl_check="${c_blue}KIỂM TRA${c_reset}"
lbl_fetch="${c_yellow}TẢI VỀ  ${c_reset}"
lbl_install="${c_green}CÀI ĐẶT ${c_reset}"
lbl_uinput="${c_purple}UINPUT  ${c_reset}"
lbl_fcitx="${c_cyan}FCITX5  ${c_reset}"
lbl_done="${c_green}HOÀN TẤT${c_reset}"
lbl_warn="${c_yellow}LƯU Ý   ${c_reset}"
lbl_err="${c_red}LỖI     ${c_reset}"
lbl_sudo="${c_red}SUDO    ${c_reset}"

# format timestamp
get_ts() {
    printf "%b[%s]%b" "$c_dim" "$(date +%T)" "$c_reset"
}

# formatted log line
log_step() {
    local lbl="$1"
    local msg="$2"
    printf "%s %b %b %b\n" "$(get_ts)" "$lbl" "$sep" "$msg"
}

# animated spinner for asynchronous tasks
spin() {
    local pid=$1
    local text=$2
    if [ ! -t 1 ]; then
        wait "$pid" 2>/dev/null || true
        return
    fi
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        local f=${frames[$i % 10]}
        printf "\r%b%s%b %b%s%b\033[K" "$c_accent" "$f" "$c_reset" "$c_dim" "$text" "$c_reset"
        i=$((i + 1))
        sleep 0.08
    done
    printf "\r\033[K"
}

# safe tty reader for pipe execution (curl ... | bash)
prompt_user() {
    local prompt_msg="$1"
    local response=""
    if [ -t 0 ]; then
        read -r -p "$prompt_msg" response
    elif [ -e /dev/tty ]; then
        read -r -p "$prompt_msg" response < /dev/tty
    else
        response="n"
    fi
    echo "$response"
}

# run command with sudo via tty
run_sudo() {
    if [ -e /dev/tty ]; then
        sudo "$@" < /dev/tty
    else
        sudo "$@"
    fi
}

# error exit
err() {
    log_step "$lbl_err" "$1"
    exit 1
}

# detect architecture
get_arch() {
    local os
    local arch
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)

    if [ "$os" != "linux" ]; then
        err "Hệ điều hành không hỗ trợ: $os (Clak chỉ hỗ trợ Linux)"
    fi

    case "$arch" in
        x86_64|amd64)
            echo "linux-x86_64"
            ;;
        *)
            err "Kiến trúc CPU không hỗ trợ: $arch (hiện tại hỗ trợ x86_64)"
            ;;
    esac
}

# display header banner
print_banner() {
    echo ""
    echo -e "  ${c_cyan}╭──────────────────────────────────────────────────────────╮${c_reset}"
    echo -e "  ${c_cyan}│${c_reset}  ${c_bold}Clak Installer${c_reset} ${c_dim}· Bộ gõ Tiếng Việt cho Fcitx5 & Wayland${c_reset}   ${c_cyan}│${c_reset}"
    echo -e "  ${c_cyan}╰──────────────────────────────────────────────────────────╯${c_reset}"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "  ${c_yellow}Chế độ: Giả lập (Dry-run / Simulation - không thay đổi hệ thống)${c_reset}"
    else
        if [ "$TARGET_MODE" = "system" ]; then
            echo -e "  ${c_dim}Cài đặt: Toàn hệ thống (/usr) - cần sudo ở bước chép file${c_reset}"
        else
            echo -e "  ${c_dim}Cài đặt: Thư mục người dùng (~/.local) - hoàn toàn không cần sudo${c_reset}"
        fi
    fi
    echo ""
}

# explain why sudo is required for uinput
print_uinput_sudo_notice() {
    echo ""
    echo -e "  ${c_red}┌─ CẦN QUYỀN QUẢN TRỊ (SUDO): CẤU HÌNH /dev/uinput ────────────────┐${c_reset}"
    echo -e "  ${c_red}│${c_reset} Clak dùng thiết bị phần cứng ảo ${c_bold}/dev/uinput${c_reset} để phát phím xóa.  ${c_red}│${c_reset}"
    echo -e "  ${c_red}│${c_reset} Tính năng này giúp ${c_green}chống nuốt chữ, mất dấu${c_reset} trên các app phức tạp: ${c_red}│${c_reset}"
    echo -e "  ${c_red}│${c_reset}  • Terminal: Kitty, Ghostty, Alacritty                          ${c_red}│${c_reset}"
    echo -e "  ${c_red}│${c_reset}  • Trình duyệt: Zen Browser, Firefox Gecko, Chromium popup      ${c_red}│${c_reset}"
    echo -e "  ${c_red}│${c_reset}  • Họ VSCode: Antigravity IDE, Cursor, VSCode, Windsurf         ${c_red}│${c_reset}"
    echo -e "  ${c_red}│${c_reset}                                                                 ${c_red}│${c_reset}"
    echo -e "  ${c_red}│${c_reset} Thao tác: Tạo file ${c_cyan}/etc/udev/rules.d/99-uinput.rules${c_reset} để cho phép    ${c_red}│${c_reset}"
    echo -e "  ${c_red}│${c_reset} user hiện tại truy cập uinput mà ${c_bold}không cần chạy app bằng root${c_reset}.  ${c_red}│${c_reset}"
    echo -e "  ${c_red}└────────────────────────────────────────────────────────────────┘${c_reset}"
    echo ""
}

# explain why sudo is required for system install
print_system_sudo_notice() {
    echo ""
    echo -e "  ${c_red}┌─ CẦN QUYỀN QUẢN TRỊ (SUDO): CÀI TOÀN HỆ THỐNG ───────────────────┐${c_reset}"
    echo -e "  ${c_red}│${c_reset} Bạn đã chọn cài đặt Clak vào thư mục hệ thống: ${c_bold}/usr/lib/fcitx5${c_reset}     ${c_red}│${c_reset}"
    echo -e "  ${c_red}│${c_reset} Cần sudo ở bước này để sao chép file addon và plugin vào thư mục. ${c_red}│${c_reset}"
    echo -e "  ${c_red}└────────────────────────────────────────────────────────────────┘${c_reset}"
    echo ""
}

# simulation flow
run_simulation() {
    print_banner

    # 1. detect os and arch
    (
        sleep 0.5
    ) &
    spin $! "đang kiểm tra kiến trúc CPU và hệ điều hành..."
    local arch
    arch=$(uname -m)
    log_step "$lbl_check" "hệ thống hợp lệ: ${c_bold}linux-${arch}${c_reset}"

    # 2. check fcitx5
    (
        sleep 0.4
    ) &
    spin $! "đang kiểm tra framework Fcitx5..."
    if command -v fcitx5 >/dev/null 2>&1; then
        local f_ver
        f_ver=$(fcitx5 --version 2>/dev/null | head -n1 || echo "fcitx5")
        log_step "$lbl_check" "đã phát hiện Fcitx5: ${c_dim}${f_ver}${c_reset}"
    else
        log_step "$lbl_warn" "chưa tìm thấy fcitx5 trên PATH (hãy cài fcitx5 để sử dụng bộ gõ)"
    fi

    # 3. resolve release tag
    local target_tag="${RELEASE_TAG:-v0.1.0}"
    (
        sleep 0.6
    ) &
    spin $! "đang truy vấn phiên bản phát hành từ GitHub API..."
    log_step "$lbl_fetch" "phiên bản cài đặt: ${c_bold}${target_tag}${c_reset}"

    # 4. download archive simulation
    local bundle_name="clak-${target_tag#v}-linux-${arch}.tar.gz"
    (
        sleep 1.0
    ) &
    spin $! "đang tải gói cài đặt ${bundle_name} (~1.8 MB)..."
    log_step "$lbl_fetch" "tải về thành công · mã băm sha256 chính xác"

    # 5. install files simulation
    local lib_dir
    local addon_dir
    local im_dir
    if [ "$TARGET_MODE" = "system" ]; then
        lib_dir="/usr/lib/fcitx5"
        addon_dir="/usr/share/fcitx5/addon"
        im_dir="/usr/share/fcitx5/inputmethod"
        print_system_sudo_notice
        (
            sleep 0.6
        ) &
        spin $! "[giả lập sudo] đang sao chép file vào ${lib_dir}..."
    else
        lib_dir="${HOME}/.local/lib/fcitx5"
        addon_dir="${HOME}/.local/share/fcitx5/addon"
        im_dir="${HOME}/.local/share/fcitx5/inputmethod"
        (
            sleep 0.5
        ) &
        spin $! "đang cài đặt vào thư mục người dùng (không cần sudo)..."
    fi

    log_step "$lbl_install" "đã cài ${c_bold}${lib_dir}/libclak.so${c_reset}"
    log_step "$lbl_install" "đã cài ${c_bold}${addon_dir}/clak.conf${c_reset}"
    log_step "$lbl_install" "đã cài ${c_bold}${im_dir}/clak.conf${c_reset}"

    # 6. check uinput permissions
    (
        sleep 0.4
    ) &
    spin $! "đang kiểm tra quyền truy cập phím ảo /dev/uinput..."
    if [ "$DEMO_UINPUT" -eq 1 ] || [ ! -w /dev/uinput ]; then
        log_step "$lbl_warn" "người dùng hiện tại chưa có quyền ghi vào /dev/uinput"
        print_uinput_sudo_notice
        (
            sleep 0.8
        ) &
        spin $! "[giả lập sudo] đang tạo file /etc/udev/rules.d/99-uinput.rules..."
        log_step "$lbl_uinput" "đã cấu hình quyền uinput thành công"
    else
        log_step "$lbl_uinput" "quyền truy cập /dev/uinput đã sẵn sàng (${c_green}sử dụng được ngay${c_reset})"
    fi

    # 7. reload fcitx5 daemon
    (
        sleep 0.5
    ) &
    spin $! "đang nạp lại daemon Fcitx5..."
    log_step "$lbl_fcitx" "đã khởi động lại Fcitx5 thành công"

    # completion summary
    echo ""
    echo -e "  ${c_green}╭──────────────────────────────────────────────────────────╮${c_reset}"
    echo -e "  ${c_green}│${c_reset}  ${c_bold}✔ Hoàn tất kiểm thử giả lập cài đặt Clak!${c_reset}               ${c_green}│${c_reset}"
    echo -e "  ${c_green}│${c_reset}  Khi chạy thật: bỏ cờ ${c_yellow}--dry-run${c_reset} để tiến hành cài đặt.    ${c_green}│${c_reset}"
    echo -e "  ${c_green}╰──────────────────────────────────────────────────────────╯${c_reset}"
    echo ""
}

# actual installation flow
run_install() {
    print_banner

    # 1. detect architecture
    (
        sleep 0.2
    ) &
    spin $! "đang xác thực kiến trúc hệ thống..."
    local arch
    arch=$(get_arch)
    log_step "$lbl_check" "kiến trúc phần cứng: ${c_bold}${arch}${c_reset}"

    # 2. check curl or wget
    local has_curl=0
    local has_wget=0
    if command -v curl >/dev/null 2>&1; then
        has_curl=1
    elif command -v wget >/dev/null 2>&1; then
        has_wget=1
    else
        err "Cần có curl hoặc wget để tải bộ cài Clak"
    fi

    if command -v fcitx5 >/dev/null 2>&1; then
        local f_ver
        f_ver=$(fcitx5 --version 2>/dev/null | head -n1 || echo "fcitx5")
        log_step "$lbl_check" "đã phát hiện Fcitx5: ${c_dim}${f_ver}${c_reset}"
    else
        log_step "$lbl_warn" "chưa tìm thấy fcitx5 trên PATH (hãy cài fcitx5 để sử dụng bộ gõ)"
    fi

    # 3. query github releases
    local release_path="/releases/latest"
    if [ -n "$RELEASE_TAG" ]; then
        release_path="/releases/tags/${RELEASE_TAG}"
    fi

    local tmp_response
    tmp_response=$(mktemp)

    (
        if [ "$has_curl" -eq 1 ]; then
            curl -sL -w "\n%{http_code}" \
                ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
                "${API_URL}/repos/${REPO}${release_path}" > "$tmp_response"
        else
            wget -q -O "$tmp_response" "${API_URL}/repos/${REPO}${release_path}" || true
        fi
    ) &
    spin $! "đang tìm kiếm bản phát hành từ GitHub..."

    local http_code
    http_code=$(tail -n1 "$tmp_response" 2>/dev/null || echo "200")
    local releases_json
    releases_json=$(sed '$d' "$tmp_response" 2>/dev/null || cat "$tmp_response")
    rm -f "$tmp_response"

    if [ "$http_code" = "404" ]; then
        err "Không tìm thấy bản phát hành nào trên GitHub. Có thể dự án chưa công bố release."
    fi

    local tag_name
    tag_name=$(echo "$releases_json" | grep '"tag_name":' | head -1 | cut -d '"' -f 4 || echo "$RELEASE_TAG")
    local download_url
    download_url=$(echo "$releases_json" | grep "browser_download_url" | grep "${arch}\.tar\.gz" | head -1 | cut -d '"' -f 4 || true)

    if [ -z "$download_url" ]; then
        err "Không tìm thấy file nén '${arch}.tar.gz' trong bản phát hành ${tag_name}"
    fi

    log_step "$lbl_fetch" "phiên bản chỉ định: ${c_bold}${tag_name}${c_reset}"

    # 4. download release archive
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' EXIT

    local archive_name
    archive_name=$(basename "$download_url")

    (
        cd "$tmp_dir"
        if [ "$has_curl" -eq 1 ]; then
            curl -sLO "$download_url"
        else
            wget -q "$download_url"
        fi
    ) &
    spin $! "đang tải gói ${archive_name}..."

    log_step "$lbl_fetch" "tải về thành công"

    # 5. extract archive
    (
        cd "$tmp_dir"
        tar -xzf "$archive_name"
    ) &
    spin $! "đang giải nén tập tin..."

    local lib_src="${tmp_dir}/usr/lib/fcitx5/libclak.so"
    local addon_src="${tmp_dir}/usr/share/fcitx5/addon/clak.conf"
    local im_src="${tmp_dir}/usr/share/fcitx5/inputmethod/clak.conf"

    if [ ! -f "$lib_src" ]; then
        err "Gói cài đặt bị lỗi: không tìm thấy file libclak.so"
    fi

    # 6. copy files (only request sudo if system install)
    local lib_dest
    local addon_dest
    local im_dest

    if [ "$TARGET_MODE" = "system" ]; then
        lib_dest="/usr/lib/fcitx5"
        addon_dest="/usr/share/fcitx5/addon"
        im_dest="/usr/share/fcitx5/inputmethod"
        print_system_sudo_notice

        run_sudo mkdir -p "$lib_dest" "$addon_dest" "$im_dest"
        run_sudo cp "$lib_src" "${lib_dest}/libclak.so"
        run_sudo cp "$addon_src" "${addon_dest}/clak.conf"
        run_sudo cp "$im_src" "${im_dest}/clak.conf"
        run_sudo chmod 755 "${lib_dest}/libclak.so"
        run_sudo chmod 644 "${addon_dest}/clak.conf" "${im_dest}/clak.conf"
    else
        lib_dest="${HOME}/.local/lib/fcitx5"
        addon_dest="${HOME}/.local/share/fcitx5/addon"
        im_dest="${HOME}/.local/share/fcitx5/inputmethod"

        (
            mkdir -p "$lib_dest" "$addon_dest" "$im_dest"
            cp "$lib_src" "${lib_dest}/libclak.so"
            cp "$addon_src" "${addon_dest}/clak.conf"
            cp "$im_src" "${im_dest}/clak.conf"
            chmod 755 "${lib_dest}/libclak.so"
            chmod 644 "${addon_dest}/clak.conf" "${im_dest}/clak.conf"
        ) &
        spin $! "đang chép file vào thư mục người dùng (${c_dim}không cần sudo${c_reset})..."
    fi

    log_step "$lbl_install" "đã chép ${c_bold}${lib_dest}/libclak.so${c_reset}"
    log_step "$lbl_install" "đã chép ${c_bold}${addon_dest}/clak.conf${c_reset}"
    log_step "$lbl_install" "đã chép ${c_bold}${im_dest}/clak.conf${c_reset}"

    # 7. check and configure uinput permission
    if [ -w /dev/uinput ] 2>/dev/null; then
        log_step "$lbl_uinput" "quyền truy cập /dev/uinput đã sẵn sàng (${c_green}OK${c_reset})"
    else
        log_step "$lbl_warn" "người dùng hiện tại chưa có quyền ghi vào /dev/uinput"
        print_uinput_sudo_notice
        local reply
        reply=$(prompt_user "Bạn có muốn cấu hình udev rule cho /dev/uinput ngay bây giờ không? [Y/n] ")
        case "$reply" in
            [yY][eE][sS]|[yY]|"")
                echo -e "  ${c_dim}Đang yêu cầu sudo để tạo rule udev...${c_reset}"
                echo 'KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess"' | run_sudo tee /etc/udev/rules.d/99-uinput.rules >/dev/null
                run_sudo udevadm trigger /dev/uinput 2>/dev/null || true
                log_step "$lbl_uinput" "đã cấu hình /dev/uinput thành công"
                ;;
            *)
                log_step "$lbl_warn" "bỏ qua cấu hình uinput. Bạn có thể cấu hình thủ công sau nếu cần"
                ;;
        esac
    fi

    # 8. reload fcitx5 daemon
    if command -v fcitx5 >/dev/null 2>&1; then
        (
            fcitx5 -r -d >/dev/null 2>&1 || true
            sleep 0.5
        ) &
        spin $! "đang khởi động lại daemon Fcitx5..."
        log_step "$lbl_fcitx" "đã nạp lại Fcitx5 với bộ gõ Clak mới"
    fi

    echo ""
    echo -e "  ${c_green}╭──────────────────────────────────────────────────────────╮${c_reset}"
    echo -e "  ${c_green}│${c_reset}  ${c_bold}✔ Cài đặt Clak ${tag_name} thành công!${c_reset}                     ${c_green}│${c_reset}"
    echo -e "  ${c_green}│${c_reset}  Vào cấu hình Fcitx5 và thêm 'Clak' vào danh sách bộ gõ. ${c_green}│${c_reset}"
    echo -e "  ${c_green}╰──────────────────────────────────────────────────────────╯${c_reset}"
    echo ""
}

# main router
if [ "$DRY_RUN" -eq 1 ]; then
    run_simulation
else
    run_install
fi
