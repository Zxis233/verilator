Rocky Linux 8.10 precompiled distribution
========================================

This fork publishes an x86_64 prerelease at:

https://github.com/Zxis233/verilator/releases/tag/rockylinux8-latest

Install or update::

   curl -fsSL https://github.com/Zxis233/verilator/releases/download/rockylinux8-latest/install.sh -o /tmp/install-verilator.sh
   sudo bash /tmp/install-verilator.sh
   verilator --version

The installer downloads and verifies a precompiled archive. It does not clone
sources, invoke a package manager, or compile Verilator. The archive contains
the installed Verilator tree, Perl, Python 3.9, Make, GCC 13, binutils, development headers,
and required libraries. Rocky Linux 8.10's base system and glibc are required.
The supplied compiler builds users' SystemVerilog models, including timing
models; this is separate from building Verilator itself.

The default installation is /opt/verilator-rockylinux8, with public Verilator
commands linked in /usr/local/bin. The compiler and Perl are private to the
installation and do not replace system commands. Previous installations are
retained in /opt/verilator-rockylinux8.previous.* when upgrading.

To install without root::

   bash /tmp/install-verilator.sh --prefix "$HOME/.local/opt/verilator" --bin-dir "$HOME/.local/bin"
   export PATH="$HOME/.local/bin:$PATH"

For offline installation, download install.sh and its matching main archive,
then run ``bash install.sh --archive /path/to/verilator-....tar.gz``.
The installer embeds the exact archive name and SHA-256. Older archives remain
available so a saved installer continues to work after a new build.

``verilator-toolchain COMMAND ...`` runs another command with the private
compiler and runtime environment. Python's standard library is bundled;
optional analysis features requiring additional Python packages are not part
of the offline model-build smoke test.

Fork maintenance
----------------

Run the ``Rocky Linux 8 prebuilt release`` workflow manually to merge upstream
stable and publish a new prerelease. A merge conflict stops the workflow for
manual resolution, preserving the fork's own files. Pushing a normal merge
to stable also builds and publishes. Never reset stable to upstream when
keeping these fork additions.

If an upstream update changes workflow files, GitHub may require an Actions
secret named WORKFLOW_TOKEN with repository contents and workflows write
permissions (classic tokens use the repo and workflow scopes). Otherwise,
merge and push that update locally with your normal Git credentials.

The workflow is also registered on the default master branch so GitHub's
manual-run button is available; it always checks out and builds stable.
Keep the fork-specific files identical on master when changing the workflow.
The fixed rockylinux8-latest tag is a prerelease download channel. GitHub's
``releases/latest`` endpoint excludes prereleases and is not used here.

Each release includes BUILD-INFO.txt, SHA256SUMS, and an archive of matching
third-party source RPMs. The source revision is recorded in BUILD-INFO.txt.
