#!/usr/bin/env bash
set -euo pipefail

# Docker 镜像管理器
# 功能：备份和恢复 Docker 镜像，确保标签信息完整保留

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查并设置压缩工具命令
setup_compress_commands() {
    # gzip命令设置
    if command -v gzip >/dev/null; then
        GZIP_CMD="gzip"
    else
        GZIP_CMD="gzip_via_docker"
    fi
    
    # zstd命令设置
    if command -v zstd >/dev/null; then
        # 检查版本兼容性
        if zstd -V 2>&1 | grep -q "incorrect library version"; then
            ZSTD_CMD="zstd_via_docker"
        else
            ZSTD_CMD="zstd"
        fi
    else
        ZSTD_CMD="zstd_via_docker"
    fi
    
    # xz命令设置
    if command -v xz >/dev/null; then
        XZ_CMD="xz"
    else
        XZ_CMD="xz_via_docker"
    fi
}

# Docker容器方式运行gzip
gzip_via_docker() {
    docker run --rm -v "$(pwd)":/data alpine \
        ash -c "apk add gzip >/dev/null && gzip $@"
}

# Docker容器方式运行zstd
zstd_via_docker() {
    docker run --rm -v "$(pwd)":/data alpine \
        ash -c "apk add zstd >/dev/null && zstd $@"
}

# Docker容器方式运行xz
xz_via_docker() {
    docker run --rm -v "$(pwd)":/data alpine \
        ash -c "apk add xz >/dev/null && xz $@"
}

# 初始化压缩命令
setup_compress_commands

# 显示菜单
show_menu() {
    clear
    echo "=============================================="
    echo "      Docker 镜像备份与恢复管理器"
    echo "=============================================="
    echo "  1. 备份所有 Docker 镜像"
    echo "  2. 从备份文件恢复 Docker 镜像"
    echo "  3. 退出"
    echo "=============================================="
    echo -n "请选择操作 (1-3): "
}

# 兼容的睡眠函数
compatible_sleep() {
    local seconds=$1
    
    # 检查是否支持小数睡眠
    if sleep 0.1 2>/dev/null; then
        sleep $seconds
    else
        # 对于不支持小数的系统，使用整数秒
        sleep $(echo "scale=0; ($seconds+0.5)/1" | bc)
    fi
}

# 显示文件处理进度
show_file_progress() {
    local file_path=$1
    local total_size=$2
    local processed_size=0
    local last_reported=0
    local report_interval=1000000  # 每1MB报告一次进度
    local start_time=$(date +%s)
    local last_percent=0  # 初始化 last_percent
    
    # 获取文件名（不含路径）
    local file_name=$(basename "$file_path")
    
    # 初始进度显示
    printf "\r  %-40s [%s] %3d%% (%dMB/%dMB)" \
        "${file_name:0:40}" \
        "                                                  " \
        0 \
        0 \
        $((total_size/1024/1024))
    
    while [ -f "$file_path" ]; do
        # 获取当前文件大小
        processed_size=$(stat -c %s "$file_path" 2>/dev/null || echo 0)
        
        # 计算百分比
        local percent=0
        if [ $total_size -gt 0 ]; then
            percent=$((processed_size * 100 / total_size))
            # 确保不超过100%
            [ $percent -gt 100 ] && percent=100
        fi
        
        # 每1MB或百分比变化大于1%时报告进度
        if [ $((processed_size - last_reported)) -ge $report_interval ] || 
           [ $percent -ge $((last_percent + 1)) ]; then
            # 显示进度条
            local bar=""
            local filled=$((percent / 2))
            for ((i=0; i<50; i++)); do
                if [ $i -lt $filled ]; then
                    bar+="■"
                else
                    bar+=" "
                fi
            done
            
            # 显示进度信息
            printf "\r  %-40s [%s] %3d%% (%dMB/%dMB)" \
                "${file_name:0:40}" \
                "$bar" \
                $percent \
                $((processed_size/1024/1024)) \
                $((total_size/1024/1024))
            
            last_reported=$processed_size
            last_percent=$percent
        fi
        
        # 使用兼容的睡眠函数
        compatible_sleep 0.5
        
        # 超时检查（如果文件存在但15秒内没有变化，退出）
        local current_time=$(date +%s)
        if [ $((current_time - start_time)) -gt 15 ]; then
            break
        fi
    done
    
    # 完成后清除进度行
    printf "\r\033[K"
}

# 快速估算压缩率
estimate_compression() {
    local tar_file=$1
    local sample_size=20000000  # 20MB采样大小
    local original_size=$(du -b "$tar_file" | cut -f1)
    
    # 如果文件小于20MB，则使用整个文件
    if [ $original_size -lt $sample_size ]; then
        sample_size=$original_size
    fi
    
    echo -e "\n正在估算压缩率 (采样$((sample_size/1024/1024))MB)..."
    
    # 创建临时采样文件
    local sample_file="${tar_file}.sample"
    head -c $sample_size "$tar_file" > "$sample_file" 2>/dev/null
    
    # 显示采样文件名
    local sample_name=$(basename "$sample_file")
    
    # 估算gzip压缩率
    echo "  估算gzip压缩率..."
    ($GZIP_CMD -c "$sample_file" > "${sample_file}.gz") &
    gzip_pid=$!
    
    # 显示压缩进度
    show_file_progress "${sample_file}.gz" $sample_size
    wait $gzip_pid
    
    gzip_size=$(du -b "${sample_file}.gz" | cut -f1)
    gzip_ratio=$(echo "scale=2; $gzip_size * $original_size / $sample_size" | bc)
    gzip_ratio_percent=$(echo "scale=1; $gzip_ratio * 100 / $original_size" | bc)
    echo -e "\r  gzip压缩: ${gzip_ratio_percent}% (约 $(echo "scale=1; $gzip_ratio/1048576" | bc)MB)"
    rm -f "${sample_file}.gz"
    
    # 估算zstd压缩率
    echo "  估算zstd压缩率..."
    ($ZSTD_CMD -q -c "$sample_file" > "${sample_file}.zst") &
    zstd_pid=$!
    
    # 显示压缩进度
    show_file_progress "${sample_file}.zst" $sample_size
    wait $zstd_pid
    
    zstd_size=$(du -b "${sample_file}.zst" | cut -f1)
    zstd_ratio=$(echo "scale=2; $zstd_size * $original_size / $sample_size" | bc)
    zstd_ratio_percent=$(echo "scale=1; $zstd_ratio * 100 / $original_size" | bc)
    echo -e "\r  zstd压缩: ${zstd_ratio_percent}% (约 $(echo "scale=1; $zstd_ratio/1048576" | bc)MB)"
    rm -f "${sample_file}.zst"
    
    # 估算xz压缩率
    echo "  估算xz压缩率..."
    ($XZ_CMD -c "$sample_file" > "${sample_file}.xz") &
    xz_pid=$!
    
    # 显示压缩进度
    show_file_progress "${sample_file}.xz" $sample_size
    wait $xz_pid
    
    xz_size=$(du -b "${sample_file}.xz" | cut -f1)
    xz_ratio=$(echo "scale=2; $xz_size * $original_size / $sample_size" | bc)
    xz_ratio_percent=$(echo "scale=1; $xz_ratio * 100 / $original_size" | bc)
    echo -e "\r  xz压缩: ${xz_ratio_percent}% (约 $(echo "scale=1; $xz_ratio/1048576" | bc)MB)"
    rm -f "${sample_file}.xz"
    
    # 清理采样文件
    rm -f "$sample_file"
    
    echo "注: 实际压缩率取决于镜像内容，文本文件多的镜像压缩率更高"
}

# 压缩备份文件
compress_backup() {
    local tar_file=$1
    local final_file
    
    echo -e "\n请选择压缩方式:"
    echo "  1. 不压缩 (保留为 .tar 文件)"
    echo "  2. gzip 压缩 (快速, 中等压缩率)"
    echo "  3. zstd 压缩 (推荐, 高速高压缩率)"
    echo "  4. xz 压缩 (最高压缩率, 但速度慢)"
    echo -n "请选择 (1-4): "
    read compress_choice
    
    case $compress_choice in
        1)
            final_file="$tar_file"
            echo "备份文件保持未压缩状态: ${tar_file##*/}"
            ;;
        2)
            final_file="${tar_file}.gz"
            echo "使用 gzip 压缩: ${tar_file##*/} -> ${final_file##*/}"
            
            # 显示压缩进度
            ($GZIP_CMD -c "$tar_file" > "$final_file") &
            gzip_pid=$!
            
            show_file_progress "$final_file" $(stat -c %s "$tar_file")
            wait $gzip_pid
            
            # 检查压缩是否成功
            if [ ! -f "$final_file" ] || [ ! -s "$final_file" ]; then
                echo -e "\r压缩失败! 使用未压缩格式"
                final_file="$tar_file"
            else
                # 删除原始tar文件
                rm -f "$tar_file"
                echo -e "\r压缩完成: ${final_file##*/}"
            fi
            ;;
        3)
            final_file="${tar_file}.zst"
            echo "使用 zstd 压缩: ${tar_file##*/} -> ${final_file##*/}"
            
            # 显示压缩进度
            ($ZSTD_CMD -q -c "$tar_file" > "$final_file") &
            zstd_pid=$!
            
            show_file_progress "$final_file" $(stat -c %s "$tar_file")
            wait $zstd_pid
            
            # 检查压缩是否成功
            if [ ! -f "$final_file" ] || [ ! -s "$final_file" ]; then
                echo -e "\r压缩失败! 使用未压缩格式"
                final_file="$tar_file"
            else
                # 删除原始tar文件
                rm -f "$tar_file"
                echo -e "\r压缩完成: ${final_file##*/}"
            fi
            ;;
        4)
            final_file="${tar_file}.xz"
            echo "使用 xz 压缩: ${tar_file##*/} -> ${final_file##*/}"
            
            # 显示压缩进度
            ($XZ_CMD -9e -c "$tar_file" > "$final_file") &
            xz_pid=$!
            
            show_file_progress "$final_file" $(stat -c %s "$tar_file")
            wait $xz_pid
            
            # 检查压缩是否成功
            if [ ! -f "$final_file" ] || [ ! -s "$final_file" ]; then
                echo -e "\r压缩失败! 使用未压缩格式"
                final_file="$tar_file"
            else
                # 删除原始tar文件
                rm -f "$tar_file"
                echo -e "\r压缩完成: ${final_file##*/}"
            fi
            ;;
        *)
            echo "无效选择，保持未压缩状态"
            final_file="$tar_file"
            ;;
    esac
    
    echo -e "\n最终备份文件: ${final_file##*/}"
    du -h "$final_file"
}

# 备份所有 Docker 镜像
backup_images() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local BACKUP_FILE="$SCRIPT_DIR/docker_images_${timestamp}.tar"
    local TMP_DIR="$SCRIPT_DIR/docker_backup_tmp"
    
    echo -e "\n开始备份 Docker 镜像..."
    
    # 检查Docker是否可用
    if ! command -v docker &> /dev/null && [ "$GZIP_CMD" == "gzip_via_docker" -o "$ZSTD_CMD" == "zstd_via_docker" -o "$XZ_CMD" == "xz_via_docker" ]; then
        echo -e "\n错误: 需要Docker来执行压缩操作，但Docker未安装或未运行!"
        echo "请安装Docker或确保Docker服务正在运行"
        return 1
    fi
    
    # 创建临时目录
    mkdir -p "$TMP_DIR"
    cd "$TMP_DIR"
    
    # 获取镜像列表
    echo "正在生成镜像列表..."
    docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" > image_list.txt
    
    if [ ! -s image_list.txt ]; then
        echo -e "\n警告: 没有找到可备份的 Docker 镜像!"
        rm -rf "$TMP_DIR"
        return 1
    fi
    
    local image_count=$(wc -l < image_list.txt)
    echo "正在保存 $image_count 个镜像..."
    
    # 分镜像保存
    local counter=0
    while IFS= read -r image; do
        counter=$((counter+1))
        # 替换特殊字符为安全文件名
        safe_name=$(echo "$image" | sed 's/[^a-zA-Z0-9._-]/_/g')
        printf "\r  保存镜像 (%d/%d): %s" $counter $image_count "${image:0:50}"
        docker save "$image" -o "${safe_name}.tar" >/dev/null 2>&1
    done < image_list.txt
    echo ""  # 换行
    
    # 打包所有镜像
    echo -e "\n创建备份文件..."
    tar cf "$BACKUP_FILE" *.tar
    
    # 清理临时文件
    cd "$SCRIPT_DIR"
    rm -rf "$TMP_DIR"
    
    # 显示原始大小
    local original_size=$(du -h "$BACKUP_FILE" | cut -f1)
    echo -e "\n原始备份文件大小: $original_size"
    
    # 快速估算压缩率
    estimate_compression "$BACKUP_FILE"
    
    # 压缩备份文件
    compress_backup "$BACKUP_FILE"
    
    # 显示结果
    echo -e "\n备份成功完成!"
}

# 解压备份文件
extract_backup() {
    local backup_file=$1
    local TMP_DIR=$2
    
    # 获取文件名（不含路径）
    local file_name=$(basename "$backup_file")
    
    case "$backup_file" in
        *.tar)
            echo "解包未压缩的备份文件: $file_name"
            tar xf "$backup_file" -C "$TMP_DIR"
            ;;
        *.tar.gz | *.tgz)
            echo "解压 gzip 压缩文件: $file_name"
            
            # 显示解压进度
            ($GZIP_CMD -dc "$backup_file" | tar x -C "$TMP_DIR") &
            extract_pid=$!
            
            show_file_progress "$backup_file" $(stat -c %s "$backup_file")
            wait $extract_pid
            
            # 检查解压是否成功
            if [ $? -ne 0 ]; then
                echo -e "\r解压失败! 请检查文件完整性"
                return 1
            else
                echo -e "\r解压完成: $file_name"
            fi
            ;;
        *.tar.zst)
            echo "解压 zstd 压缩文件: $file_name"
            
            # 显示解压进度
            ($ZSTD_CMD -dc "$backup_file" | tar x -C "$TMP_DIR") &
            extract_pid=$!
            
            show_file_progress "$backup_file" $(stat -c %s "$backup_file")
            wait $extract_pid
            
            # 检查解压是否成功
            if [ $? -ne 0 ]; then
                echo -e "\r解压失败! 请检查文件完整性"
                return 1
            else
                echo -e "\r解压完成: $file_name"
            fi
            ;;
        *.tar.xz)
            echo "解压 xz 压缩文件: $file_name"
            
            # 显示解压进度
            ($XZ_CMD -dc "$backup_file" | tar x -C "$TMP_DIR") &
            extract_pid=$!
            
            show_file_progress "$backup_file" $(stat -c %s "$backup_file")
            wait $extract_pid
            
            # 检查解压是否成功
            if [ $? -ne 0 ]; then
                echo -e "\r解压失败! 请检查文件完整性"
                return 1
            else
                echo -e "\r解压完成: $file_name"
            fi
            ;;
        *)
            echo "未知文件格式，尝试直接解包: $file_name"
            
            # 显示解压进度
            (tar xf "$backup_file" -C "$TMP_DIR") &
            extract_pid=$!
            
            show_file_progress "$backup_file" $(stat -c %s "$backup_file")
            wait $extract_pid
            
            tar_status=$?
            if [ $tar_status -ne 0 ]; then
                echo -e "\r无法解压备份文件! 请确保文件格式正确"
                return 1
            else
                echo -e "\r解压完成: $file_name"
            fi
            ;;
    esac
}

# 从备份文件恢复镜像
restore_images() {
    # 查找备份文件
    local backup_files=($(ls "$SCRIPT_DIR"/docker_images_*.* 2>/dev/null))
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        echo -e "\n错误: 在脚本目录找不到备份文件!"
        echo "请将备份文件放在脚本目录: $SCRIPT_DIR"
        return 1
    fi
    
    # 检查Docker是否可用
    if ! command -v docker &> /dev/null && [ "$GZIP_CMD" == "gzip_via_docker" -o "$ZSTD_CMD" == "zstd_via_docker" -o "$XZ_CMD" == "xz_via_docker" ]; then
        echo -e "\n错误: 需要Docker来执行解压操作，但Docker未安装或未运行!"
        echo "请安装Docker或确保Docker服务正在运行"
        return 1
    fi
    
    # 显示备份文件列表
    echo -e "\n可用的备份文件:"
    for i in "${!backup_files[@]}"; do
        echo "  $((i+1)). ${backup_files[$i]##*/}"
    done
    
    # 选择文件
    echo -en "\n请选择要恢复的备份文件 (1-${#backup_files[@]}): "
    read choice
    
    # 验证输入
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backup_files[@]} ]; then
        echo "无效的选择!"
        return 1
    fi
    
    local selected_file="${backup_files[$((choice-1))]}"
    local TMP_DIR="$SCRIPT_DIR/docker_restore_tmp"
    
    # 创建临时目录
    mkdir -p "$TMP_DIR"
    
    # 解压/解包备份文件
    echo -e "\n处理备份文件: ${selected_file##*/}"
    extract_backup "$selected_file" "$TMP_DIR" || {
        rm -rf "$TMP_DIR"
        return 1
    }
    
    # 进入临时目录
    cd "$TMP_DIR"
    
    # 加载所有镜像
    local img_files=($(ls *.tar 2>/dev/null))
    local img_count=${#img_files[@]}
    
    if [ $img_count -eq 0 ]; then
        echo "错误: 备份文件中未找到镜像文件!"
        cd "$SCRIPT_DIR"
        rm -rf "$TMP_DIR"
        return 1
    fi
    
    echo -e "\n正在恢复 $img_count 个镜像..."
    local counter=0
    for img_tar in "${img_files[@]}"; do
        counter=$((counter+1))
        printf "\r  恢复镜像 (%d/%d): %s" $counter $img_count "${img_tar:0:30}"
        docker load -i "$img_tar" >/dev/null 2>&1
    done
    echo ""  # 换行
    
    # 清理临时文件
    cd "$SCRIPT_DIR"
    rm -rf "$TMP_DIR"
    
    # 显示结果
    echo -e "\n恢复成功完成!"
    echo "已恢复的镜像:"
    docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" | head -10
    [ $(docker images | wc -l) -gt 10 ] && echo "  ... (更多镜像未显示)"
}

# 主程序
while true; do
    show_menu
    read choice
    
    case $choice in
        1)
            backup_images
            ;;
        2)
            restore_images
            ;;
        3)
            echo -e "\n退出程序。"
            exit 0
            ;;
        *)
            echo -e "\n无效选择，请重新输入!"
            ;;
    esac
    
    echo -en "\n按回车键继续..."
    read
done