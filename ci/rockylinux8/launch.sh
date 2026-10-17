#!/bin/bash
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
set -euo pipefail

# The public commands may be symlinked outside the installation prefix.
prefix=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
command_name=${0##*/}
export PATH="$prefix/bin:$prefix/toolchain/bin:$PATH"
export LD_LIBRARY_PATH="$prefix/runtime/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PERL5LIB="$prefix/runtime/lib64/perl5:$prefix/runtime/share/perl5:$prefix/runtime/lib64/perl5/vendor_perl:$prefix/runtime/share/perl5/vendor_perl"
export VERILATOR_ROOT="$prefix/share/verilator"

case "$command_name" in
    gcc|cc)
        exec "$prefix/toolchain/bin/gcc" --sysroot="$prefix/sysroot" "$@"
        ;;
    g++|c++)
        exec "$prefix/toolchain/bin/g++" --sysroot="$prefix/sysroot" "$@"
        ;;
    make|perl|xargs)
        exec "$prefix/runtime/bin/$command_name" "$@"
        ;;
    python3)
        export PYTHONHOME="$prefix/runtime"
        exec "$prefix/runtime/bin/python3" "$@"
        ;;
    verilator-toolchain)
        exec "$@"
        ;;
    *)
        exec "$prefix/libexec/$command_name" "$@"
        ;;
esac
