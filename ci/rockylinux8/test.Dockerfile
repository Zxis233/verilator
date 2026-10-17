# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
ARG ROCKY_IMAGE=rockylinux/rockylinux:8.10
FROM ${ROCKY_IMAGE}

# Model a target with an existing alternatives-managed system Python.
RUN dnf -y --setopt=install_weak_deps=False install python3.12 chkconfig \
    && alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 312 \
    && alternatives --set python3 /usr/bin/python3.12 \
    && python3 -c 'import sys; assert sys.version_info[:2] == (3, 12), sys.version' \
    && dnf clean all
