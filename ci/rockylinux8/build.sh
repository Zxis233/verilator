#!/bin/bash
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
set -euo pipefail

cd "$(dirname "$0")/../.."
repository=${GITHUB_REPOSITORY:-Zxis233/verilator}
release_tag=${RELEASE_TAG:-rockylinux8-latest}
build_id=${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}
version=$(sed -n 's/^AC_INIT(\[Verilator\],\[\([^ ]*\) .*/\1/p' configure.ac)
archive_name="verilator-${version}-rockylinux8-x86_64-${build_id}.tar.gz"
sources_name="sources-rockylinux8-x86_64-${build_id}.tar.gz"
mkdir -p dist

# All package-manager activity is confined to this build container.
dnf -y install epel-release dnf-plugins-core
dnf config-manager --set-enabled powertools
dnf -y install autoconf bison diffutils file findutils flex \
    gcc-toolset-13-binutils gcc-toolset-13-gcc-c++ git gzip help2man \
    make perl-core python39 tar which xz zlib-devel
ln -sfn /usr/bin/python3.9 /usr/local/bin/python3
# The checkout belongs to the runner user, while this container runs as root.
git config --global --add safe.directory "$(pwd)"
source_sha=$(git rev-parse HEAD)
# shellcheck disable=SC1091
source /opt/rh/gcc-toolset-13/enable
unset VERILATOR_ROOT
autoconf
./configure --prefix=/opt/verilator-rockylinux8 --enable-ccwarn \
    --enable-light-debug --disable-jemalloc --disable-tcmalloc CC=gcc CXX=g++
make -j "${BUILD_JOBS:-2}"
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
make DESTDIR="$stage" install
package_root="$stage/opt/verilator-rockylinux8"
mv "$package_root/bin" "$package_root/libexec"
mkdir -p "$package_root/bin" "$package_root/runtime/bin" "$package_root/runtime/lib64" \
    "$package_root/runtime/share" "$package_root/toolchain" \
    "$package_root/sysroot/usr/lib64" "$package_root/share/third-party-licenses"
touch "$package_root/.verilator-rockylinux8"

# Relocate the vendor compiler, and give it its own headers and linker sysroot.
cp -aL /opt/rh/gcc-toolset-13/root/usr/. "$package_root/toolchain/"
cp -a /usr/include "$package_root/sysroot/usr/"
ln -s usr/lib64 "$package_root/sysroot/lib64"
sysroot_packages=(glibc glibc-devel glibc-headers kernel-headers libgcc libstdc++ zlib zlib-devel)
for rpm_package in "${sysroot_packages[@]}"; do
    while IFS= read -r path; do
        if [[ $path == /usr/lib64/* || $path == /lib64/* ]]; then
            if [[ -f $path ]]; then
                install -D -m 644 "$path" "$package_root/sysroot/usr/lib64/${path#*/lib64/}"
            fi
        fi
    done < <(rpm -ql "$rpm_package")
done
# Toolset linker scripts live outside the sysroot; '=' makes their system
# library references follow --sysroot instead of the build host's /usr.
while IFS= read -r -d '' path; do
    if ! file -b "$path" | grep -q ELF; then
        sed -i -e 's| /usr/lib64/| =/usr/lib64/|g' \
            -e 's| /lib64/| =/lib64/|g' "$path"
    fi
done < <(find "$package_root/toolchain" -type f -name '*.so' -print0)

cp -aL /usr/bin/perl /usr/bin/make "$package_root/runtime/bin/"
cp -aL /usr/bin/python3.9 "$package_root/runtime/bin/python3"
cp -aL /usr/lib64/python3.9 "$package_root/runtime/lib64/"
cp -aL /usr/lib64/perl5 "$package_root/runtime/lib64/"
cp -aL /usr/share/perl5 "$package_root/runtime/share/"

# ldd reports the transitive shared-library closure. Rocky's base glibc stays
# system-provided; loading a private glibc through LD_LIBRARY_PATH is unsafe.
while IFS= read -r -d '' path; do
    if file -b "$path" | grep -q ELF; then
        while IFS= read -r library; do
            owner=$(rpm -qf --qf '%{NAME}' "$library")
            if [[ $owner != glibc ]]; then
                cp -L "$library" "$package_root/runtime/lib64/"
                printf '%s\n' "$library" >> "$stage/runtime-files"
            fi
        done < <(ldd "$path" | awk '/=> \// {print $3} /^[[:space:]]*\// {print $1}')
    fi
done < <(find "$package_root/toolchain" "$package_root/runtime" "$package_root/libexec" \
    -type f -perm /111 -print0)

for path in "$package_root/libexec/"*; do
    install -m 755 ci/rockylinux8/launch.sh "$package_root/bin/${path##*/}"
done
for name in gcc g++ cc c++ make perl python3 verilator-toolchain; do
    install -m 755 ci/rockylinux8/launch.sh "$package_root/bin/$name"
done
# pkg-config is the one installed metadata file that embeds its old prefix.
# shellcheck disable=SC2016
sed -i 's|^prefix=.*|prefix=${pcfiledir}/../..|' "$package_root/share/pkgconfig/verilator.pc"
# shellcheck disable=SC2016
sed -i 's|^includedir=.*|includedir=${prefix}/share/verilator/include|' "$package_root/share/pkgconfig/verilator.pc"
sed -i -e 's|^AR =.*|AR = ar|' -e 's|^PERL =.*|PERL = perl|' \
    -e 's|^PYTHON3 =.*|PYTHON3 = python3|' "$package_root/share/verilator/include/verilated.mk"
cp LICENSE "$package_root/share/verilator/LICENSE"
cp -a /usr/share/licenses/. "$package_root/share/third-party-licenses/"
cp ci/rockylinux8/README.rst "$package_root/README.rst"

{
    printf 'version=%s\nsource_sha=%s\nrepository=%s\n' "$version" "$source_sha" "$repository"
    printf 'built_at=%s\nimage=%s\n' "$(date -u +%FT%TZ)" "${ROCKY_IMAGE:-rockylinux/rockylinux:8.10}"
    printf '\nInstalled build-container RPMs (name, version, source RPM):\n'
    rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}.%{ARCH}\t%{SOURCERPM}\n' | sort
} > dist/BUILD-INFO.txt
cp dist/BUILD-INFO.txt "$package_root/BUILD-INFO.txt"

# Publish matching sources for the redistributed compiler/runtime packages.
{
    rpm -q --qf '%{SOURCERPM}\n' "${sysroot_packages[@]}" make perl-interpreter python39
    find /opt/rh/gcc-toolset-13/root/usr /usr/include /usr/lib64/perl5 /usr/share/perl5 /usr/lib64/python3.9 \
        -type f -print0 | xargs -0 rpm -qf --qf '%{SOURCERPM}\n'
    sort -u "$stage/runtime-files" | xargs rpm -qf --qf '%{SOURCERPM}\n'
} | sort -u > "$package_root/SOURCE-RPMS.txt"
mkdir -p "$stage/sources"
mapfile -t source_nvrs < <(sed 's/\.src\.rpm$//' "$package_root/SOURCE-RPMS.txt")
dnf download --source --destdir "$stage/sources" "${source_nvrs[@]}"
tar -czf "dist/$sources_name" -C "$stage" sources
tar -czf "dist/$archive_name" -C "$stage/opt" verilator-rockylinux8

export repository release_tag archive_name
export archive_sha256
archive_sha256=$(sha256sum "dist/$archive_name" | cut -d ' ' -f 1)
python3 - <<'PY'
import os
from pathlib import Path

text = Path("ci/rockylinux8/install.sh").read_text()
for key, value in {
    "REPOSITORY": os.environ["repository"],
    "RELEASE_TAG": os.environ["release_tag"],
    "ARCHIVE": os.environ["archive_name"],
    "SHA256": os.environ["archive_sha256"],
}.items():
    text = text.replace("@" + key + "@", value)
Path("dist/install.sh").write_text(text)
PY
chmod 755 dist/install.sh
(cd dist && sha256sum "$archive_name" "$sources_name" install.sh BUILD-INFO.txt > SHA256SUMS)
