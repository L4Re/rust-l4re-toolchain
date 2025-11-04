Rust Toolchain for L4Re
=======================

This builds the Rust compiler by taking the relevant Rust compiler components
with a few L4Re adoptions.

This build works close to Rust upstream. PRs are open to include the patches
from this repo into Rust's repositories.

If you do not want the script to change your Rust environment, call:

    $ ./checkout_and_build.sh init-rust

which sets up a local Rust environment for the build and test process.

To build the toolchain, call the script like this:

    $ ./checkout_and_build.sh gen-toolchain

After this, the toolchain can be found in ``rust-l4re-toolchain`` directory,
and ``rust-l4re-toolchain.tar.xz`` file.


Testing Routine
===============

To check whether the build worked and leads to working binaries, please run
the following:

    $ ./checkout_and_build.sh hookup-toolchain
    $ ./checkout_and_build.sh build-kernel
    $ ./checkout_and_build.sh build-hello

For running it you need to have QEMU installed for the respective target
architectures.

    $ ./checkout_and_build.sh run aarch64
    $ ./checkout_and_build.sh run x86_64

