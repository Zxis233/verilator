#!/bin/bash
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
# Release generation replaces the four @...@ values below.
set -euo pipefail

repository='@REPOSITORY@'
release_tag='@RELEASE_TAG@'
archive_name='@ARCHIVE@'
archive_sha256='@SHA256@'
prefix=/opt/verilator-rockylinux8
bin_dir=/usr/local/bin
local_archive=
link_commands=1

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'EOF'
Usage: bash install.sh [--prefix DIR] [--bin-dir DIR] [--no-symlinks]
                       [--archive FILE]

Deploy the precompiled Rocky Linux 8.10 x86_64 distribution. Installation
does not use a package manager, check out sources, or compile anything.

Defaults: --prefix /opt/verilator-rockylinux8 --bin-dir /usr/local/bin
Requires an existing system python3 (tested with Python 3.12).
Use --archive with a previously downloaded release archive for offline use.
For a user installation, select a writable prefix and --no-symlinks.
EOF
}

while (($#)); do
    case "$1" in
        --prefix|--bin-dir|--archive)
            (($# >= 2)) || die "Missing value for $1"
            case "$1" in
                --prefix) prefix=$2 ;;
                --bin-dir) bin_dir=$2 ;;
                --archive) local_archive=$2 ;;
            esac
            shift 2
            ;;
        --no-symlinks) link_commands=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done

[[ -r /etc/os-release ]] || die 'Cannot identify the operating system'
# shellcheck disable=SC1091
source /etc/os-release
[[ $ID == rocky && $VERSION_ID == 8.10 ]] || die 'This package requires Rocky Linux 8.10'
[[ $(uname -m) == x86_64 ]] || die 'This package requires x86_64'
command -v python3 >/dev/null || die 'System python3 is required; configure it before installing'
python3 --version || die 'System python3 cannot run'
[[ $archive_sha256 =~ ^[0-9a-f]{64}$ ]] || die 'Use the generated install.sh from the release assets'
[[ $prefix == /* && $prefix != / && ! $prefix =~ [[:space:]] ]] || die 'Prefix must be an absolute path without spaces'
[[ $bin_dir == /* && ! $bin_dir =~ [[:space:]] ]] || die 'Bin directory must be an absolute path without spaces'
[[ ! -L $prefix ]] || die 'Prefix must not be a symbolic link'
prefix=$(realpath -m -- "$prefix")
[[ $prefix != / ]] || die 'Prefix must not be the filesystem root'
if [[ -e $prefix && ! -f $prefix/.verilator-rockylinux8 ]]; then
    die "Refusing to replace an unmanaged directory: $prefix"
fi
if ((link_commands)); then
    bin_dir=$(realpath -m -- "$bin_dir")
    [[ $bin_dir != "$prefix" && $bin_dir != "$prefix/"* ]] \
        || die 'Bin directory must be outside the installation prefix'
    for name in verilator verilator_coverage verilator_gantt verilator_profcfunc verilator-toolchain; do
        if [[ -e $bin_dir/$name && ! -L $bin_dir/$name ]]; then
            die "Refusing to replace an existing file: $bin_dir/$name"
        fi
    done
fi

download_dir=$(mktemp -d)
staging=
cleanup() {
    rm -rf -- "$download_dir"
    if [[ -n $staging && -d $staging ]]; then rm -rf -- "$staging"; fi
}
trap cleanup EXIT

if [[ -n $local_archive ]]; then
    [[ -f $local_archive ]] || die "Archive not found: $local_archive"
    archive=$(realpath -- "$local_archive")
else
    command -v curl >/dev/null || die 'curl is required to download; alternatively use --archive FILE'
    archive="$download_dir/$archive_name"
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
        "https://github.com/$repository/releases/download/$release_tag/$archive_name" \
        --output "$archive"
fi
printf '%s  %s\n' "$archive_sha256" "$archive" | sha256sum --check --status \
    || die 'Archive SHA-256 verification failed'

mkdir -p -- "$(dirname -- "$prefix")"
staging=$(mktemp -d "${prefix}.install.XXXXXX")
tar -xzf "$archive" --strip-components=1 -C "$staging"
[[ -f $staging/.verilator-rockylinux8 ]] || die 'The archive is not a Verilator distribution'
"$staging/bin/verilator" --version
"$staging/bin/g++" --version | head -n 1

backup=
if [[ -d $prefix ]]; then
    backup="${prefix}.previous.$(date -u +%Y%m%dT%H%M%SZ).$$"
    mv -- "$prefix" "$backup"
fi
if ! mv -- "$staging" "$prefix"; then
    if [[ -n $backup ]]; then mv -- "$backup" "$prefix"; fi
    die 'Could not activate the new installation'
fi
staging=

if ((link_commands)); then
    mkdir -p -- "$bin_dir"
    for name in verilator verilator_coverage verilator_gantt verilator_profcfunc verilator-toolchain; do
        ln -sfn -- "$prefix/bin/$name" "$bin_dir/$name"
    done
fi
printf '\nInstalled in %s\n' "$prefix"
printf 'Version: '
"$prefix/bin/verilator" --version
printf 'Toolchain: %s/bin/verilator-toolchain g++ --version\n' "$prefix"
if ((!link_commands)); then printf 'Run %s/bin/verilator to use this installation.\n' "$prefix"; fi
if [[ -n $backup ]]; then printf 'Previous installation retained in %s\n' "$backup"; fi
