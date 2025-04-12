CURRENT_DIR=$(dirname $0)
bash $CURRENT_DIR/patches/undo_patch.sh

# OTA需要创建/base/update/updater/resources/pz200目录，创建后编译完成删除
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)                  # 获取当前脚本所在目录并转换为绝对路径
OpenHarmony_src=$(dirname $(dirname $(dirname $(dirname "$SCRIPT_DIR")))) # 多次嵌套 dirname 获取OpenHarmony源码根目录
rm -rf $OpenHarmony_src/base/update/updater/resources/pz200