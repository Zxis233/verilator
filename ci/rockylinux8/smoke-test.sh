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
archive=$(find /work/dist -maxdepth 1 -name 'verilator-*.tar.gz' -print)
bash /work/dist/install.sh --archive "$archive"
verilator --version
verilator_coverage --version
test "$(verilator --get-supported COROUTINES)" = 1

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
test -n "$(find /opt -maxdepth 1 -name 'verilator-rockylinux8.previous.*' -print)"
