#!/bin/bash

# Number of scripts to generate
NUM_SCRIPTS=10

# Base directories and naming conventions
BASE_WATCH_DIR="/mnt/up"
BASE_MOUNT_POINT="/root/check"
BASE_LOG="/tmp/rclone_out"
BASE_SCRIPT_NAME="yeniup"

# Template for the script
TEMPLATE_SCRIPT=$(cat <<'EOF'
#!/bin/bash

WATCH_DIR="{{WATCH_DIR}}"
FINAL_REMOTE="crypt:"
MOUNT_POINT="{{MOUNT_POINT}}"
MAX_USAGE=5
SLEEP_BETWEEN=60

ACCOUNTS_PARENT="/root/set/accounts"
GROUP_SIZE=6
MAX_GROUP_INDEX=16

LOG_TMP="{{LOG_TMP}}"

pick_random_folder() {
    local folders=( $(find "$ACCOUNTS_PARENT" -mindepth 1 -maxdepth 1 -type d) )
    if [[ ${#folders[@]} -eq 0 ]]; then
        echo "HATA: SA klasörü yok => $ACCOUNTS_PARENT"
        exit 1
    fi
    local r=$((RANDOM % ${#folders[@]}))
    echo "${folders[$r]}"
}

pick_random_group_index() {
    echo $((RANDOM % MAX_GROUP_INDEX + 1))
}

get_group_sa_files() {
    local folder="$1"
    local g="$2"
    local start=$(( (g-1)*GROUP_SIZE + 1 ))
    local end=$(( g*GROUP_SIZE ))
    local result=()

    for ((i=start; i<=end; i++)); do
        local num=$(printf "%04d" "$i")
        local found=( $(find "$folder" -maxdepth 1 -type f -name "*-sa-$num@*.json") )
        if [[ ${#found[@]} -gt 0 ]]; then
            result+=( "${found[0]}" )
        fi
    done
    echo "${result[@]}"
}

check_sa_usage() {
    local sa_file="$1"
    mkdir -p "$MOUNT_POINT"
    rclone mount \
        "$FINAL_REMOTE" \
        "$MOUNT_POINT" \
        --daemon \
        --drive-service-account-file "$sa_file"
    sleep 3

    local used
    used=$(df -h "$MOUNT_POINT" | tail -1 | awk '{print $5}' | sed 's/%//')
    fusermount -u "$MOUNT_POINT" 2>/dev/null
    sleep 1

    [[ -z "$used" ]] && used=100
    echo "$used"
}

upload_with_retry() {
    local src="$1"
    local sa_file="$2"

    while true; do
        rm -f "$LOG_TMP"
        echo "[UPLOAD] $src => $FINAL_REMOTE (SA=$sa_file)"

        rclone move \
            "$src" \
            "$FINAL_REMOTE" \
            --drive-service-account-file "$sa_file" \
            --progress \
            --transfers 2 \
            --max-transfer=14.3G \
            --cutoff-mode=cautious \
            --exclude '/.txt' \
            --drive-pacer-burst=1200 \
            --drive-pacer-min-sleep=10000ms \
            --drive-upload-cutoff 1000T \
            --tpslimit 3 \
            --tpslimit-burst 3 \
            --drive-chunk-size 128M \
            --no-traverse \
            --log-level INFO \
            -P \
            2>&1 | tee "$LOG_TMP"

        local rc=${PIPESTATUS[0]}
        if [[ $rc -eq 0 ]]; then
            echo "[OK] Yükleme tamam: $src"
            break
        else
            if grep -q "429" "$LOG_TMP"; then
                echo "[WARN] 429 => 1 dk bekle..."
                sleep 60
            elif grep -q "403" "$LOG_TMP"; then
                echo "[WARN] 403 => daily limit / erişim hatası, 1 dk bekle..."
                sleep 60
            elif grep -q "max transfer limit reached" "$LOG_TMP"; then
                echo "[ERR] Max transfer limit => pointer veya chunk yüklenemeyebilir!"
                sleep 5
                break
            else
                echo "[ERR] Beklenmeyen hata, rc=$rc"
                cat "$LOG_TMP"
                echo "5 sn sonra tekrar dene..."
                sleep 5
            fi
        fi
    done
}

while true; do
    fpt_file=$(find "$WATCH_DIR" -maxdepth 1 -type f -name "*.fpt" | head -n1)
    if [[ -z "$fpt_file" ]]; then
        echo "[INFO] Yeni .fpt yok, 5 sn bekle..."
        sleep 5
        continue
    fi

    base_name=$(basename "$fpt_file")
    echo "[INFO] Yeni .fpt bulundu => $base_name"

    echo "[CHUNK] rclone move $fpt_file => $FINAL_REMOTE"
    rclone move "$fpt_file" "$FINAL_REMOTE" -P
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "[ERR] chunker hata, kod=$rc. 5 sn bekle..."
        sleep 5
        continue
    fi
done
EOF
)

# Generate scripts
for i in $(seq 1 $NUM_SCRIPTS); do
    WATCH_DIR="${BASE_WATCH_DIR}${i}"
    MOUNT_POINT="${BASE_MOUNT_POINT}${i}"
    LOG_FILE="${BASE_LOG}${i}.log"
    SCRIPT_NAME="${BASE_SCRIPT_NAME}${i}.sh"

    # Replace placeholders and create the script
    echo "$TEMPLATE_SCRIPT" | sed \
        -e "s|{{WATCH_DIR}}|$WATCH_DIR|" \
        -e "s|{{MOUNT_POINT}}|$MOUNT_POINT|" \
        -e "s|{{LOG_TMP}}|$LOG_FILE|" \
        > "$SCRIPT_NAME"

    # Make the script executable
    chmod +x "$SCRIPT_NAME"

    echo "Generated script: $SCRIPT_NAME"
done
