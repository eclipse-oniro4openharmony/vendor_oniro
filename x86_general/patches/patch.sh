# Copyright (c) 2024 Diemit <598757652@qq.com>
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#!/bin/bash

CURRENT_DIR=$(pwd)
SOURCE_ROOT_DIR=$CURRENT_DIR/../../../../

cd $SOURCE_ROOT_DIR/arkcompiler/runtime_core
patch -p1 < $CURRENT_DIR/arkcompiler/runtime_core/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/base/security/selinux_adapter
patch -p1 < $CURRENT_DIR/base/security/selinux_adapter/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/base/hiviewdfx/faultloggerd
patch -p1 < $CURRENT_DIR/base/hiviewdfx/faultloggerd/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/base/inputmethod/imf
patch -p1 < $CURRENT_DIR/base/inputmethod/imf/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/base/msdp/device_status
patch -p1 < $CURRENT_DIR/base/msdp/device_status/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/base/powermgr/power_manager
patch -p1 < $CURRENT_DIR/base/powermgr/power_manager/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/base/startup/appspawn
patch -p1 < $CURRENT_DIR/base/startup/appspawn/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/base/startup/init
patch -p1 < $CURRENT_DIR/base/startup/init/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/base/web/webview
patch -p1 < $CURRENT_DIR/base/web/webview/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/build
patch -p1 < $CURRENT_DIR/build/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/developtools/integration_verification
patch -p1 < $CURRENT_DIR/developtools/integration_verification/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/developtools/profiler
patch -p1 < $CURRENT_DIR/developtools/profiler/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/drivers/external_device_manager
patch -p1 < $CURRENT_DIR/drivers/external_device_manager/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/drivers/peripheral
patch -p1 < $CURRENT_DIR/drivers/peripheral/0001-OHPC-X86.patch

# cd $SOURCE_ROOT_DIR/foundation/ability/ability_runtime
# patch -p1 < $CURRENT_DIR/foundation/ability/ability_runtime/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/foundation/distributeddatamgr/datamgr_service
patch -p1 < $CURRENT_DIR/foundation/distributeddatamgr/datamgr_service/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/foundation/filemanagement/storage_service
patch -p1 < $CURRENT_DIR/foundation/filemanagement/storage_service/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/foundation/graphic/graphic_2d
patch -p1 < $CURRENT_DIR/foundation/graphic/graphic_2d/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/foundation/graphic/graphic_3d
patch -p1 < $CURRENT_DIR/foundation/graphic/graphic_3d/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/foundation/multimedia/camera_framework
patch -p1 < $CURRENT_DIR/foundation/multimedia/camera_framework/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/foundation/multimedia/image_framework
patch -p1 < $CURRENT_DIR/foundation/multimedia/image_framework/0001-OHPC-X86.patch

# cd $SOURCE_ROOT_DIR/foundation/multimodalinput/input
# patch -p1 < $CURRENT_DIR/foundation/multimodalinput/input/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/third_party/e2fsprogs
patch -p1 < $CURRENT_DIR/third_party/e2fsprogs/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/third_party/lzma
patch -p1 < $CURRENT_DIR/third_party/lzma/0001-OHPC-X86.patch

# cd $SOURCE_ROOT_DIR/third_party/mesa3d
# patch -p1 < $CURRENT_DIR/third_party/mesa3d/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/third_party/mindspore
patch -p1 < $CURRENT_DIR/third_party/mindspore/0001-OHPC-X86.patch

cd $SOURCE_ROOT_DIR/third_party/musl
patch -p1 < $CURRENT_DIR/third_party/musl/0001-OHPC-X86.patch
