#!/bin/bash
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
set -euo pipefail

# Only the system Python is preinstalled; the deployment has no network.
for name in g++ make perl; do
    if command -v "$name"; then
        printf 'Unexpected preinstalled tool: %s\n' "$name" >&2
        exit 1
    fi
done
python3 -c 'import sys; assert sys.version_info[:2] == (3, 12), sys.version'
system_python=$(python3 -c 'import sys; print(sys.executable)')
python_target=$(readlink -f "$(command -v python3)")
archives=(/work/dist/verilator-*.tar.gz)
archive=${archives[0]}
expect_failure() {
    if "$@"; then
        printf 'Command unexpectedly succeeded: %s\n' "$*" >&2
        exit 1
    fi
}
run_as_user() {
    python3 - "$@" <<'PY'
import os
import pwd
import sys

user = pwd.getpwnam("nobody")
os.setgroups([])
os.setgid(user.pw_gid)
os.setuid(user.pw_uid)
os.execvp(sys.argv[1], sys.argv[1:])
PY
}
: > /tmp/bad-archive.tar.gz
expect_failure bash /work/dist/install.sh --archive /tmp/bad-archive.tar.gz \
    --prefix /tmp/invalid-install --no-symlinks
test ! -e /tmp/invalid-install
expect_failure bash /work/dist/install.sh --archive "$archive" \
    --prefix /tmp/nested-install --bin-dir /tmp/nested-install/bin
bash /work/dist/install.sh --archive "$archive"
test ! -e /opt/verilator-rockylinux8/bin/python3
test ! -e /opt/verilator-rockylinux8/runtime/bin/python3
python_files=(/opt/verilator-rockylinux8/runtime/lib64/python* /opt/verilator-rockylinux8/runtime/lib64/libpython*)
for path in "${python_files[@]}"; do
    test ! -e "$path"
done
test "$(verilator-toolchain python3 -c 'import sys; print(sys.executable)')" = "$system_python"
test "$(readlink -f "$(command -v python3)")" = "$python_target"
run_as_user verilator --version
run_as_user verilator_coverage --version
run_as_user verilator_gantt --help >/dev/null
run_as_user verilator_profcfunc --help >/dev/null
run_as_user verilator-toolchain python3 /opt/verilator-rockylinux8/share/verilator/bin/verilator_ccache_report --help >/dev/null
test "$(run_as_user verilator --get-supported COROUTINES)" = 1
ln -s /opt/verilator-rockylinux8 /tmp/prefix-alias
expect_failure bash /work/dist/install.sh --archive "$archive" \
    --prefix /tmp/prefix-alias --no-symlinks

cat > /tmp/smoke.sv <<'EOF'
module smoke;
  timeunit 1ns;
  timeprecision 1ns;
  initial begin
    #5;
    if ($time != 5) $fatal(1, "unexpected time");
    $display("TIMING_SMOKE_OK");
    $finish;
  end
endmodule
EOF
run_as_user verilator --binary --timing -j 2 --top-module smoke \
    --Mdir /tmp/obj_dir /tmp/smoke.sv
run_as_user /tmp/obj_dir/Vsmoke | tee /tmp/smoke.log
grep -q TIMING_SMOKE_OK /tmp/smoke.log

# The installed tree must work outside the configure-time /opt prefix too.
bash /work/dist/install.sh --archive "$archive" --prefix /tmp/relocated --no-symlinks
run_as_user /tmp/relocated/bin/verilator --binary --timing -j 2 --top-module smoke \
    --Mdir /tmp/relocated_obj /tmp/smoke.sv
run_as_user /tmp/relocated_obj/Vsmoke | grep TIMING_SMOKE_OK

# Updating keeps the previous installation rather than deleting it.
bash /work/dist/install.sh --archive "$archive"
backups=(/opt/verilator-rockylinux8.previous.*)
test -d "${backups[0]}"
run_as_user verilator --version
