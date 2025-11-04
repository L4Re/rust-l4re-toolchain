#! /bin/bash
#
# by adam@l4re.org

set -xe

BASEDIR=$PWD
SCRIPTDIR=$(dirname $(realpath $0))

export RUSTUP_HOME=$BASEDIR/rustup
export CARGO_HOME=$BASEDIR/cargo
export PATH=$CARGO_HOME/bin:$RUSTUP_HOME/toolchains/nightly-x86_64-unknown-linux-gnu/bin:$PATH

cmd=$1

init_rust()
{
  rm -fr $RUSTUP_HOME
  rm -fr $CARGO_HOME

  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > rustup-init
  chmod +x rustup-init
  ./rustup-init --no-modify-path -y

  rustup show
  rustup toolchain list
}

checkout_rust()
{
  mkdir -p out
  git -C out clone --reference /data/adam/rust https://github.com/rust-lang/rust.git
  git -C out clone https://github.com/rust-lang/libc.git

  git -C out/rust checkout 41f2b6b39e7526a28d50ff6918dda6de48add5e4
  git -C out/rust apply $SCRIPTDIR/patches/rust.patch

  git -C out/libc checkout 6e1b073e3e4032d4bf7ade404a347cf9f82e08cb
  git -C out/libc apply $SCRIPTDIR/patches/libc.patch

  echo 'libc = { path = "../../libc", version = "0.2.177" }' >> out/rust/library/Cargo.toml
  sed -i 's/version = "0\.2\.177"/path = "..\/..\/..\/libc", &/g' out/rust/library/std/Cargo.toml
  sed -i 's/^version =.*/version = "0.2.177"/g' out/libc/Cargo.toml

  cp $SCRIPTDIR/config.toml out/rust
}

build_rust()
{
  pushd out/rust
  ./x.py check
  ./x.py build --stage 2 library -j$(nproc)
  popd
}

build_l4re()
{
  mkdir out/l4re
  pushd out/l4re

  cat >l4re-core.patch <<_EOF
--- a/l4re/util/libs/Makefile
+++ b/l4re/util/libs/Makefile
@@ -7,6 +7,9 @@
 PC_LIBS       := %{-link-libc:%{shared:--whole-archive -l4re-util.p --no-whole-archive;:lib4re-util.ofl}}
 PC_LIBS_PIC   :=
 
+# Add dependency on libc.so for lib4re-util.so, to ensure INIT function of
+# libc/libpthread is called by ldso before lib4re-util.
+LDFLAGS  += \$(if \$(DO_THE_INIT_DEPENDENCY_HACK),-lc)
 PICFLAGS += -DSHARED=1
 CXXFLAGS += -DL4_NO_RTTI -fno-rtti -fno-exceptions

_EOF

  git clone --depth 1 https://github.com/kernkonzept/mk l4
  git clone --depth 1 https://github.com/kernkonzept/l4re-core l4/pkg/l4re-core

  # we build more for testing, for the sysroot the above two are sufficient
  git clone --depth 1 https://github.com/kernkonzept/bootstrap l4/pkg/bootstrap
  git clone --depth 1 https://github.com/kernkonzept/drivers-frst l4/pkg/drivers-frst
  git clone --depth 1 https://github.com/kernkonzept/libfdt l4/pkg/libfdt

  p=$PWD
  (cd l4/pkg/l4re-core && patch -p 1 -i $p/l4re-core.patch)
  if grep -qv libgcc-crt l4/Makefile; then
    (cd l4 && patch -p 1 -i $SCRIPTDIR/patches/0001-sysroot-install-libgcc-crt-as-well.patch)
  fi

  cp l4/mk/defconfig/config.amd64 defconfig-amd64
  echo "CONFIG_COMPILER_RT_USE_TOOLCHAIN_LIBGCC=n" >> defconfig-amd64
  rm -rf build.amd64
  make -C l4 -j $(nproc) B="$PWD/build.amd64" DEFCONFIG="$PWD/defconfig-amd64"
  make -C build.amd64 -j $(nproc) olddefconfig
  make -C build.amd64 -j $(nproc)
  make -C build.amd64 -j $(nproc) sysroot
  rm build.amd64/pkg/l4re-core/l4re/util/libs/OBJ*std-l4f/lib4re-util*
  make -C build.amd64/pkg/l4re-core/l4re/util/libs -j $(nproc) DO_THE_INIT_DEPENDENCY_HACK=1
  cp build.amd64/pkg/l4re-core/l4re/util/libs/OBJ*std-l4f/lib4re-util* build.amd64/sysroot/usr/lib

  cp l4/mk/defconfig/config.arm64-virt-v8a defconfig-arm64
  echo "CONFIG_COMPILER_RT_USE_TOOLCHAIN_LIBGCC=n" >> defconfig-arm64
  rm -rf build.arm64
  make -C l4 -j $(nproc) B="$PWD/build.arm64" DEFCONFIG="$PWD/defconfig-arm64"
  make -C build.arm64 -j $(nproc) olddefconfig
  make -C build.arm64 -j $(nproc)
  make -C build.arm64 -j $(nproc) sysroot
  rm build.arm64/pkg/l4re-core/l4re/util/libs/OBJ*std-l4f/lib4re-util*
  make -C build.arm64/pkg/l4re-core/l4re/util/libs -j $(nproc) DO_THE_INIT_DEPENDENCY_HACK=1
  cp build.arm64/pkg/l4re-core/l4re/util/libs/OBJ*std-l4f/lib4re-util* build.arm64/sysroot/usr/lib

  popd
}

build_kernel()
{
  mkdir -p out
  git -C out clone --depth 1 https://github.com/kernkonzept/fiasco
  pushd out/fiasco
  make B=build-arm64 T=arm64-virt-el2
  make B=build-amd64 T=amd64-dfl
  make -C build-arm64 -j $(nproc)
  make -C build-amd64 -j $(nproc)
  popd
}

package_toolchain()
{
  rm -rf rust-l4re-toolchain
  cp -r out/rust/build/host/stage2/ rust-l4re-toolchain

  cp -r out/l4re/build.amd64/sysroot/usr/lib/*   rust-l4re-toolchain/lib/rustlib/x86_64-unknown-l4re-uclibc/lib/self-contained/
  cp -r out/l4re/build.amd64/sysroot/usr/include rust-l4re-toolchain/lib/rustlib/x86_64-unknown-l4re-uclibc/lib/self-contained/

  cp -r out/l4re/build.arm64/sysroot/usr/lib/*   rust-l4re-toolchain/lib/rustlib/aarch64-unknown-l4re-uclibc/lib/self-contained/
  cp -r out/l4re/build.arm64/sysroot/usr/include rust-l4re-toolchain/lib/rustlib/aarch64-unknown-l4re-uclibc/lib/self-contained/

  chmod -R og=u-w rust-l4re-toolchain
  tar -cJv --owner l4re --group rust -f rust-l4re-toolchain.tar.xz rust-l4re-toolchain

}

hookup_toolchain()
{
  rustup toolchain link l4re rust-l4re-toolchain
  rustup toolchain list
}

build_hello()
{
  which rustc 
  rustup toolchain list

  # probably only works on a x86_64 host
  rustc +l4re --target x86_64-unknown-l4re-uclibc $SCRIPTDIR/hello_world/src/main-simple.rs
  rustc +l4re --target aarch64-unknown-l4re-uclibc -C linker=aarch64-linux-gnu-ld $SCRIPTDIR/hello_world/src/main-simple.rs

  pushd $SCRIPTDIR/hello_world
  cargo +l4re build --target=x86_64-unknown-l4re-uclibc
  cargo +l4re build --target=aarch64-unknown-l4re-uclibc --config target.aarch64-unknown-l4re-uclibc.linker=\"aarch64-linux-gnu-ld\"
  popd
}

case "$cmd" in
  init-rust) init_rust;;
  checkout-rust) checkout_rust;;
  build-rust) build_rust;;
  build-l4re) build_l4re;;
  build-kernel) build_kernel;;
  package-toolchain) package_toolchain;;
  build-hello) build_hello;;
  hookup-toolchain) hookup_toolchain;;

  run)
    case "$2" in
      x86_64|aarch64) mode=$2;;
      *) echo "Please specify x86_64 or aarch64"; exit 1;;
    esac

    echo 'local L4 = require("L4");' > hello_world.cfg
    echo 'L4.default_loader:start({}, "rom/hello_world");' >> hello_world.cfg

cat > modules.list <<_EOF
entry hello_world
kernel fiasco -serial_esc
roottask moe rom/hello_world.cfg
module l4re
module ned
module hello_world.cfg
module hello_world
_EOF

    [[ $mode = x86_64  ]] && make -C out/l4re/build.amd64 qemu E=hello_world MODULES_LIST=$PWD/modules.list MODULE_SEARCH_PATH=$PWD/out/fiasco/build-amd64:$SCRIPTDIR/hello_world/target/x86_64-unknown-l4re-uclibc/debug:$PWD QEMU_OPTIONS="-vnc :4 -serial stdio -m 1024"
    [[ $mode = aarch64 ]] && make -C out/l4re/build.arm64 qemu E=hello_world MODULES_LIST=$PWD/modules.list MODULE_SEARCH_PATH=$PWD/out/fiasco/build-arm64:$SCRIPTDIR/hello_world/target/aarch64-unknown-l4re-uclibc/debug:$PWD QEMU_OPTIONS="-vnc :4 -serial stdio -m 1024 -M virt,virtualization=true -cpu cortex-a57"

    ;;

  shell)
    echo "Launch shell with environment set"
    echo export PATH=$PATH
    $SHELL 
    echo "Exiting environment"
    ;;
  gen-toolchain)
    checkout_rust
    build_rust
    build_l4re
    package_toolchain
    ;;
  clean)
    rm -rf out
    ;;
  *)
    echo "unknown command"
    ;;
esac
