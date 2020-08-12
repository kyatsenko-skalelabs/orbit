#!/bin/bash -x
#
# Copyright (c) 2020 The Orbit Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

export CONAN_PROFILE="msvc2017_relwithdebinfo"
source "$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../" >/dev/null 2>&1 && pwd )/build.sh"
