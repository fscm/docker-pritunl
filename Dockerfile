FROM fscm/debian:buster as build

ARG BUSYBOX_VERSION="1.31.0"
ARG GOLANG_VERSION="1.13.3"
ARG IPTABLES_VERSION="1.8.3"
ARG OPENSSL_VERSION="1.1.1d"
ARG OPENVPN_VERSION="2.4.7"
ARG PYTHON_VERSION="2.7.17"
ARG PRITUNL_VERSION="1.29.2232.32"

ENV \
  LANG=C.UTF-8 \
  DEBIAN_FRONTEND=noninteractive

COPY files/ /root/

WORKDIR /root

RUN \
# dependencies
  apt-get -qq update && \
  apt-get -qq -y -o=Dpkg::Use-Pty=0 --no-install-recommends install \
    bison \
    blt-dev \
    bzip2 \
    ca-certificates \
    curl \
    dpkg-dev \
    file \
    flex \
    gcc \
    git \
    libbluetooth-dev \
    libbz2-dev \
    libc-dev \
    libdb-dev \
    libexpat1-dev \
    libffi-dev \
    libgdbm-dev \
    libgpm2 \
    liblz4-dev \
    liblzo2-dev \
    libmnl-dev \
    libncurses-dev \
    libnetfilter-conntrack-dev \
    libpam0g-dev \
    libpcap-dev \
    libpkcs11-helper1-dev \
    libreadline-dev \
    libsqlite3-dev \
    libtinfo-dev \
    libtool \
    make \
    sharutils \
    tar \
    tk-dev \
    zlib1g-dev \
    > /dev/null 2>&1 && \
# build structure
  for folder in bin sbin lib lib64; do install --directory --owner=root --group=root --mode=0755 /build/usr/${folder}; ln -s usr/${folder} /build/${folder}; done && \
  for folder in tmp data; do install --directory --owner=root --group=root --mode=1777 /build/${folder}; done && \
# copy tests
  #install --directory --owner=root --group=root --mode=0755 /build/usr/bin && \
  install --owner=root --group=root --mode=0755 --target-directory=/build/usr/bin /root/tests/* && \
# copy scripts
  install --owner=root --group=root --mode=0755 --target-directory=/build/usr/bin /root/scripts/* && \
# busybox
  curl --silent --location --retry 3 "https://busybox.net/downloads/binaries/${BUSYBOX_VERSION}-i686-uclibc/busybox" \
    -o /build/usr/bin/busybox && \
  chmod +x /build/usr/bin/busybox && \
  for p in [ basename cat cp date diff dirname du env free getopt grep gzip hostname id ip kill killall less ln ls mkdir mknod mktemp more mv netstat pgrep ping ps pwd rm sed sh sort stty sysctl tar tr wget; do ln /build/usr/bin/busybox /build/usr/bin/${p}; done && \
  for p in arp ifconfig ip ipaddr iptunnel nameif route slattach; do ln /build/usr/bin/busybox /build/usr/sbin/${p}; done && \
  for p in arp ifconfig ip ipaddr iptunnel nameif route slattach; do ln -s /build/usr/bin/busybox /usr/sbin/${p}; done && \
# openssl
  install --directory /src/openssl && \
  curl --silent --location --retry 3 "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" \
    | tar xz --no-same-owner --strip-components=1 -C /src/openssl && \
  cd /src/openssl && \
  ./config -Wl,-rpath=/usr/lib/x86_64-linux-gnu \
    --prefix="/usr" \
    --openssldir="/etc/ssl" \
    --libdir="/usr/lib/$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
    no-idea \
    no-mdc2 \
    no-rc5 \
    no-zlib \
    no-ssl3 \
    no-ssl3-method \
    enable-rfc3779 \
    enable-cms \
    enable-ec_nistp_64_gcc_128 && \
  make --silent -j "$(getconf _NPROCESSORS_ONLN)" && \
  make --silent install_sw install_ssldirs DESTDIR=/build INSTALL='install -p' && \
  find /build -depth -type f -name c_rehash -delete && \
  find /build -depth \( \( -type d -a \( -name include -o -name pkgconfig -o -name share \) \) -o \( -type f -a \( -name '*.a' -o -name '*.la' -o -name '*.dist' \) \) \) -exec rm -rf '{}' + && \
  cd - && \
# use built openssl
  rm -f /usr/lib/x86_64-linux-gnu/libssl.so* /usr/bin/openssl && \
  ln -s /build/usr/lib/x86_64-linux-gnu/libssl.so* /usr/lib/x86_64-linux-gnu/ && \
  ln -s /build/usr/bin/openssl /usr/bin/openssl && \
  #echo '/build/usr/lib/x86_64-linux-gnu' > /etc/ld.so.conf.d/00_build.conf && \
  #ldconfig && \
# iptables
  install --directory /src/iptables && \
  curl --silent --location --retry 3 "https://www.netfilter.org/projects/iptables/files/iptables-${IPTABLES_VERSION}.tar.bz2" \
    | tar xj --no-same-owner --strip-components=1 -C /src/iptables && \
  cd /src/iptables && \
  ./configure LDFLAGS="-Wl,-rpath=/usr/lib/x86_64-linux-gnu" \
    --quiet \
    --prefix="/usr" \
    --libdir="/usr/lib/$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
    --with-xtlibdir="/usr/lib/$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)/xtables" \
    --enable-connlabel \
    --enable-bpf-compiler \
    --enable-nfsynproxy \
    --disable-devel \
    --disable-libipq \
    --disable-nftables \
    --disable-shared && \
  make --silent -j "$(getconf _NPROCESSORS_ONLN)" && \
  make --silent install DESTDIR=/build INSTALL='install -p' && \
  find /build -depth \( \( -type d -a \( -name include -o -name pkgconfig -o -name share \) \) -o \( -type f -a \( -name '*.a' -o -name '*.la' -o -name '*.dist' \) \) \) -exec rm -rf '{}' + && \
  cd - && \
# openvpn
  install --directory /src/openvpn && \
  curl --silent --location --retry 3 "https://swupdate.openvpn.org/community/releases/openvpn-${OPENVPN_VERSION}.tar.gz" \
    | tar xz --no-same-owner --strip-components=1 -C /src/openvpn && \
  cd /src/openvpn && \
  ./configure LDFLAGS="-Wl,-rpath=/usr/lib/x86_64-linux-gnu" \
    --quiet \
    --prefix="/usr" \
    --libdir="/usr/lib/$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
    --with-crypto-library=openssl \
    --enable-iproute2 \
    --enable-pkcs11 \
    --enable-shared \
    --enable-x509-alt-username \
    --disable-debug \
    --disable-static && \
  make --silent -j "$(getconf _NPROCESSORS_ONLN)" && \
  make --silent install DESTDIR=/build INSTALL='install -p' && \
  find /build -depth \( \( -type d -a \( -name include -o -name pkgconfig -o -name share \) \) -o \( -type f -a \( -name '*.a' -o -name '*.la' -o -name '*.dist' \) \) \) -exec rm -rf '{}' + && \
  cd - && \
# golang
  install --directory --owner=root --group=root --mode=0755 /opt/golang && \
  curl --silent --location --retry 3 "https://dl.google.com/go/go${GOLANG_VERSION}.linux-amd64.tar.gz" \
    | tar xz --no-same-owner --strip-components=1 -C /opt/golang/ && \
# python2
  install --directory /src/python && \
  curl --silent --location --retry 3 "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-${PYTHON_VERSION}.tgz" \
    | tar xz --no-same-owner --strip-components=1 -C /src/python/ && \
  cd /src/python && \
  rm -rf Modules/expat && \
  rm -rf Modules/zlib && \
  for d in darwin libffi libffi_arm_wince libffi_msvc libffi_osx; do rm -r Modules/_ctypes/${d}; done && \
  for f in md5module.c md5.c shamodule.c sha256module.c sha512module.c; do rm Modules/${f}; done && \
  ./configure \
    CFLAGS="-Wdate-time -D_FORTIFY_SOURCE=2 -g -fstack-protector-strong -Wformat -Werror=format-security" \
    LDFLAGS="-Wl,-z,relro" \
    --quiet \
    --prefix="/usr" \
    --enable-ipv6 \
    --enable-shared \
    --enable-unicode=ucs4 \
    --with-computed-gotos \
    --with-dbmliborder=bdb:gdbm \
    --with-fpectl \
    --with-system-expat \
    --with-system-ffi \
    --with-ensurepip=install && \
  make --silent -j "$(getconf _NPROCESSORS_ONLN)" && \
  make --silent install DESTDIR=/build INSTALL='install -p' && \
  #find /build -depth \( \( -type d -a \( -name include -o -name pkgconfig -o -name share \) \) -o \( -type f -a \( -name '*.a' -o -name '*.la' -o -name '*.dist' \) \) \) -exec rm -rf '{}' + && \
  find /build -depth \( \( -type d -a \( -name pkgconfig -o -name share \) \) -o \( -type f -a \( -name '*.a' -o -name '*.la' -o -name '*.dist' \) \) \) -exec rm -rf '{}' + && \
  find /build -depth \( \( -type d -a \( -name test -o -name tests \) \) -o \( -type f -a \( -name '*.pyc' -o -name '*.pyo' \) \) \) -exec rm -rf '{}' + && \
  cd - && \
# use built python
  #rm -f /usr/lib/x86_64-linux-gnu/libpython*.so* /usr/bin/python* && \
  #ln -s /build/usr/lib/x86_64-linux-gnu/libpython*.so* /usr/lib/x86_64-linux-gnu/ && \
  ln -s /build/usr/bin/python2.7 /usr/bin/python2.7 && \
# pritunl
  PATH=$PATH:/opt/golang/bin GOBIN=/build/usr/bin go get -u github.com/pritunl/pritunl-dns && \
  PATH=$PATH:/opt/golang/bin GOBIN=/build/usr/bin go get -u github.com/pritunl/pritunl-web && \
  install --directory /src/pritunl && \
  curl --silent --location --retry 3 "https://github.com/pritunl/pritunl/archive/${PRITUNL_VERSION}.tar.gz" \
    | tar xz --no-same-owner --strip-components=1 -C /src/pritunl/ && \
  cd /src/pritunl && \
  for f in $(grep -Rl 'var/lib/pritunl' ./*); do sed -i 's,var/lib/pritunl,data/pritunl,g' ${f}; done && \
  for f in $(grep -Rl 'var/log' ./*); do sed -i 's,var/log,data/pritunl/log,g' ${f}; done && \
  sed -i -e '/log_path/ s/:.*/: "",/' data/etc/pritunl.conf && \
  PATH="$PATH:/build/usr/bin" LD_LIBRARY_PATH="/build/usr/lib" /usr/bin/python2.7 -E setup.py --quiet build --no-systemd && \
  PATH="$PATH:/build/usr/bin" LD_LIBRARY_PATH="/build/usr/lib" CFLAGS="-I/build/usr/include" CPPFLAGS="-I/build/usr/include" LDFLAGS="-L/build/usr/lib" pip install --quiet --requirement requirements.txt && \
  PATH="$PATH:/build/usr/bin" LD_LIBRARY_PATH="/build/usr/lib" /usr/bin/python2.7 -E setup.py --quiet install --no-systemd --root /build --prefix "/usr" && \
  mv /build/etc/pritunl.conf /build/etc/pritunl.conf.orig && \
  ln -s /data/pritunl/pritunl.conf /build/etc/pritunl.conf && \
  find /build -depth -type d -name include -exec rm -rf '{}' + && \
  find /build -depth \( \( -type d -a \( -name test -o -name tests \) \) -o \( -type f -a \( -name '*.pyc' -o -name '*.pyo' \) \) \) -exec rm -rf '{}' + && \
  cd - && \
# system settings
  install --directory --owner=root --group=root --mode=0755 /build/run/systemd && \
  echo 'docker' > /build/run/systemd/container && \
# lddcp
  curl --silent --location --retry 3 "https://raw.githubusercontent.com/fscm/tools/master/lddcp/lddcp" -o ./lddcp && \
  chmod +x ./lddcp && \
  ./lddcp $(for f in `find /build/ -type f -executable`; do echo "-p $f "; done) $(for f in `find /lib/x86_64-linux-gnu/ \( -name 'libnss*' -o -name 'libresolv*' \)`; do echo "-l $f "; done) -d /build && \
# ca certificates
  install --owner=root --group=root --mode=0644 --target-directory=/build/etc/ssl/certs /etc/ssl/certs/*.pem && \
  chroot /build openssl rehash /etc/ssl/certs



FROM scratch

LABEL \
  maintainer="Frederico Martins <https://hub.docker.com/u/fscm/>"

EXPOSE \
  80 \
  443 \
  1194 \
  1194/udp

COPY --from=build \
  /build .

VOLUME ["/data"]

WORKDIR /data

ENV LANG=C.UTF-8

ENTRYPOINT ["/usr/bin/run"]

CMD ["help"]
