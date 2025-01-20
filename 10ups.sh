#!/usr/bin/env bash
#
# This script will generate 10 separate scripts (script1.sh ... script10.sh).
# Each generated script will have:
#   - WATCH_DIR="/mnt/upX"    (X from 1 to 10)
#   - MOUNT_POINT="/root/checkX"    (X from 1 to 10)
#   - And the rclone move step uses "chunkX:" instead of "chunk1:".
#
# After generation, each script is standalone and can be run independently.
# Just remember to `chmod +x scriptX.sh` to make them executable.

# We'll store all the template code in a variable and substitute the parts
# that change for each script.

for i in $(seq 1 10); do

  cat <<EOF > "yeniup${i}.sh"
#!/usr/bin/env bash

WATCH_DIR="/mnt/up${i}"
FINAL_REMOTE="crypt:"
MOUNT_POINT="/root/check${i}"
MAX_USAGE=5
SLEEP_BETWEEN=60

ACCOUNTS_PARENT="/root/set/accounts"
GROUP_SIZE=6
MAX_GROUP_INDEX=16

LOG_TMP="/tmp/rclone_out${i}.log"

pick_random_folder() {
    local folders=( \$(find "\$ACCOUNTS_PARENT" -mindepth 1 -maxdepth 1 -type d) )
    if [[ \${#folders[@]} -eq 0 ]]; then
        echo "HATA: SA klasörü yok => \$ACCOUNTS_PARENT"
        exit 1
    fi
    local r=\$((RANDOM % \${#folders[@]}))
    echo "\${folders[\$r]}"
}

pick_random_group_index() {
    echo \$((RANDOM % MAX_GROUP_INDEX + 1))
}

# Grup => (g-1)*6+1 .. g*6 => *-sa-00XX@*.json
get_group_sa_files() {
    local folder="\$1"
    local g="\$2"
    local start=\$(( (\$g-1)*GROUP_SIZE + 1 ))
    local end=\$(( \$g*GROUP_SIZE ))
    local result=()

    for ((i=start; i<=end; i++)); do
        local num=\$(printf "%04d" "\$i")
        local found=( \$(find "\$folder" -maxdepth 1 -type f -name "*-sa-\$num@*.json") )
        if [[ \${#found[@]} -gt 0 ]]; then
            result+=( "\${found[0]}" )
        fi
    done
    echo "\${result[@]}"
}

check_sa_usage() {
    local sa_file="\$1"
    mkdir -p "\$MOUNT_POINT"
    rclone mount \\
        "\$FINAL_REMOTE" \\
        "\$MOUNT_POINT" \\
        --daemon \\
        --drive-service-account-file "\$sa_file"
    sleep 3

    local used
    used=\$(df -h "\$MOUNT_POINT" | tail -1 | awk '{print \$5}' | sed 's/%//')
    fusermount -u "\$MOUNT_POINT" 2>/dev/null
    sleep 1

    [[ -z "\$used" ]] && used=100
    echo "\$used"
}

# Tek dosya (kaynak), SA => rclone move
upload_with_retry() {
    local src="\$1"
    local sa_file="\$2"

    while true; do
        rm -f "\$LOG_TMP"
        echo "[UPLOAD] \$src => \$FINAL_REMOTE (SA=\$sa_file)"

        rclone move \\
            "\$src" \\
            "\$FINAL_REMOTE" \\
            --drive-service-account-file "\$sa_file" \\
            --progress \\
            --transfers 2 \\
            --max-transfer=14.3G \\
            --cutoff-mode=cautious \\
            --exclude '/.txt' \\
            --drive-pacer-burst=1200 \\
            --drive-pacer-min-sleep=10000ms \\
            --drive-upload-cutoff 1000T \\
            --tpslimit 3 \\
            --tpslimit-burst 3 \\
            --drive-chunk-size 128M \\
            --no-traverse \\
            --log-level INFO \\
            -P \\
            2>&1 | tee "\$LOG_TMP"

        local rc=\${PIPESTATUS[0]}
        if [[ \$rc -eq 0 ]]; then
            echo "[OK] Yükleme tamam: \$src"
            break
        else
            if grep -q "429" "\$LOG_TMP"; then
                echo "[WARN] 429 => 1 dk bekle..."
                sleep 60
            elif grep -q "403" "\$LOG_TMP"; then
                echo "[WARN] 403 => daily limit / erişim hatası, 1 dk bekle..."
                sleep 60
            elif grep -q "max transfer limit reached" "\$LOG_TMP"; then
                echo "[ERR] Max transfer limit => pointer veya chunk yüklenemeyebilir!"
                sleep 5
                break
            else
                echo "[ERR] Beklenmeyen hata, rc=\$rc"
                cat "\$LOG_TMP"
                echo "5 sn sonra tekrar dene..."
                sleep 5
            fi
        fi
    done
}


########################
# ANA DÖNGÜ
########################

while true; do
    # 1) /mnt/up${i}/ => .fpt
    fpt_file=\$(find "\$WATCH_DIR" -maxdepth 1 -type f -name "*.fpt" | head -n1)
    if [[ -z "\$fpt_file" ]]; then
        echo "[INFO] Yeni .fpt yok, 5 sn bekle..."
        sleep 5
        continue
    fi

    base_name=\$(basename "\$fpt_file")
    echo "[INFO] Yeni .fpt bulundu => \$base_name"

    # 2) rclone move => chunk${i}:
    echo "[CHUNK] rclone move \$fpt_file => chunk${i}:"
    rclone move "\$fpt_file" "chunk${i}:" -P
    rc=\$?
    if [[ \$rc -ne 0 ]]; then
        echo "[ERR] chunker hata, kod=\$rc. 5 sn bekle..."
        sleep 5
        continue
    fi

    # Orijinal .fpt silinir, .rclone_chunk.* + pointer .fpt chunker nereye isterse
    # 3) chunk dosyalarını isme göre bul
    chunk_files=( \$(find / -type f -name "\${base_name}.rclone_chunk.*" 2>/dev/null | sort) )
    if [[ \${#chunk_files[@]} -eq 0 ]]; then
        echo "[ERR] .rclone_chunk.* yok => unknown path"
        sleep 5
        continue
    fi
    echo "[INFO] Parça sayısı: \${#chunk_files[@]}"

    # Pointer => same name
    pointer_file=\$(find / -type f -name "\${base_name}" 2>/dev/null | head -n1)
    if [[ -z "\$pointer_file" ]]; then
        echo "[WARN] Pointer dosyası yok => \$base_name"
    else
        echo "[INFO] Pointer => \$pointer_file"
    fi

    # 4) 6 SA grubunu bul (tek sefer)
    six_sas=()
    while true; do
        folder=\$(pick_random_folder)
        grp=\$(pick_random_group_index)
        echo "[INFO] Denenen => \$folder, grup=\$grp"

        SA_LIST=( \$(get_group_sa_files "\$folder" "\$grp") )
        if [[ \${#SA_LIST[@]} -ne 6 ]]; then
            echo "[WARN] 6 SA yok => retry"
            sleep 2
            continue
        fi

        all_empty=true
        for sajson in "\${SA_LIST[@]}"; do
            usage=\$(check_sa_usage "\$sajson")
            echo "   \$sajson => %\$usage"
            if [[ \$usage -gt \$MAX_USAGE ]]; then
                echo "[INFO] SA dolu => başka grup dene"
                all_empty=false
                break
            fi
        done
        if \$all_empty; then
            echo "[OK] Bu 6 SA boş => kullanıyoruz"
            six_sas=( "\${SA_LIST[@]}" )
            break
        fi
        sleep 2
    done

    # 5) chunk i => SA[i % 6], SON PART => önce pointer, sonra chunk
    total=\${#chunk_files[@]}
    for i_chunk in "\${!chunk_files[@]}"; do
        part_file="\${chunk_files[\$i_chunk]}"
        idx=\$(( i_chunk % 6 ))
        sa_file="\${six_sas[\$idx]}"

        if [[ \$i_chunk -eq \$(( total - 1 )) ]]; then
            # SON PART
            echo "[LAST PART] => önce pointer, sonra part (aynı SA)"

            # 5a) pointer
            if [[ -n "\$pointer_file" && -f "\$pointer_file" ]]; then
                echo "[POINTER FIRST] => \$pointer_file"
                upload_with_retry "\$pointer_file" "\$sa_file"
            fi

            # 5b) part (son chunk)
            echo "[CHUNK SECOND] => \$part_file"
            upload_with_retry "\$part_file" "\$sa_file"

        else
            # Normal
            echo "[PART] \$part_file => SA[\$idx] => \$sa_file"
            upload_with_retry "\$part_file" "\$sa_file"
        fi
    done

    # 6) Temizlik
    for cf in "\${chunk_files[@]}"; do
        rm -f "\$cf"
    done
    if [[ -n "\$pointer_file" ]]; then
        rm -f "\$pointer_file"
    fi

    echo "[OK] Tüm chunk + pointer bitti => 1 dk bekle..."
    sleep "\$SLEEP_BETWEEN"
done

EOF

  # Make the script executable
  chmod +x "yeniup${i}.sh"
  echo "Created yeniup${i}.sh"
done
