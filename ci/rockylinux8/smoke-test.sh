#!/bin/bash
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
set -euo pipefail

# This container has no network, language tools, or development headers.
for name in g++ make perl python3; do
    if command -v "$name"; then
        printf 'Unexpected preinstalled tool: %s\n' "$name" >&2
        exit 1
    fi
done
archives=(/work/dist/verilator-*.tar.gz)
archive=${archives[0]}
expect_failure() {
    if "$@"; then
        printf 'Command unexpectedly succeeded: %s\n' "$*" >&2
        exit 1
    fi
}
: > /tmp/bad-archive.tar.gz
expect_failure bash /work/dist/install.sh --archive /tmp/bad-archive.tar.gz \
    --prefix /tmp/invalid-install --no-symlinks
test ! -e /tmp/invalid-install
expect_failure bash /work/dist/install.sh --archive "$archive" \
    --prefix /tmp/nested-install --bin-dir /tmp/nested-install/bin
bash /work/dist/install.sh --archive "$archive"
verilator --version
verilator_coverage --version
test "$(verilator --get-supported COROUTINES)" = 1
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
verilator --binary --timing -j 2 --top-module smoke \
    --Mdir /tmp/obj_dir /tmp/smoke.sv
/tmp/obj_dir/Vsmoke | tee /tmp/smoke.log
grep -q TIMING_SMOKE_OK /tmp/smoke.log

# The installed tree must work outside the configure-time /opt prefix too.
bash /work/dist/install.sh --archive "$archive" --prefix /tmp/relocated --no-symlinks
/tmp/relocated/bin/verilator --binary --timing -j 2 --top-module smoke \
    --Mdir /tmp/relocated_obj /tmp/smoke.sv
/tmp/relocated_obj/Vsmoke | grep TIMING_SMOKE_OK

# Updating keeps the previous installation rather than deleting it.
bash /work/dist/install.sh --archive "$archive"
backups=(/opt/verilator-rockylinux8.previous.*)
test -d "${backups[0]}"
