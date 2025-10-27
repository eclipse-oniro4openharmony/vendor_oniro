#!/bin/bash
# Copyright (C) 2025 Huawei Inc.
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

PATCH_DIR=$(cd $(dirname $0);pwd)/patches
SOURCE_ROOT_DIR=$PATCH_DIR/../../../../../

# Initialize an empty array to store the paths of found .patch files
declare -a patch_files

# Use the find command to search for all .patch files in the current directory and its subdirectories
# and add their relative paths to the array
while IFS= read -r -d '' file; do
    patch_files+=("$file")
done < <(find $PATCH_DIR -type f -name "*.patch" -print0 | sort)

# Iterate through the array and output the relative path of each .patch file
for path in "${patch_files[@]}"; do
    # Use realpath --relative-to to compute the relative path (if available)
    if command -v realpath &> /dev/null && realpath --relative-to="$PATCH_DIR" "$path" 2>/dev/null; then
        relative_path="$(realpath --relative-to="$PATCH_DIR" $(dirname $path))"
    else
        # If realpath --relative-to is not available, compute the relative path manually
        # Note: This method may be less accurate than realpath, especially when dealing with symlinks
        common_prefix=""
        # Find the common prefix of the base directory and the path (simplified case, assumes no symlinks)
        while [[ "$path" != "$PATCH_DIR" && "$path" != "${path%/*}" ]]; do
            if [[ "$PATCH_DIR" == "${PATCH_DIR%/*}"*"${path##*/}" ]]; then
                # The common prefix is the base directory minus its last directory level
                common_prefix="${PATCH_DIR%/*}"
                break
            fi
            path="${path%/*}"
        done
        # Compute the relative path by removing the common prefix and adding appropriate ../
        relative_parts=()
        while [[ "$path" != "$common_prefix" ]]; do
            relative_parts+=("../")
            path="${path%/*}"
        done
        # Combine to form the final relative path
        relative_path="${relative_parts[*]#/}"
        # Remove extra leading ../ if the base directory is the path itself
        relative_path="${relative_path#../}"
    fi
    # Output the relative path
    echo "patching $path"
    cd $SOURCE_ROOT_DIR/$relative_path
    patch -R -p1 < $path
done

