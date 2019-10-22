FROM fscm/debian:stretch as build

ARG BUSYBOX_VERSION="1.30.0"
ARG GOLANG_VERSION="1.11.5"
ARG PYTHON_VERSION="2.7.15"
ARG PRITUNL_VERSION="1.29.1979.98"

ENV \
  LANG=C.UTF-8 \
  DEBIAN_FRONTEND=noninteractive

COPY files/ /root/

WORKDIR /root

RUN \
  apt-get -qq update && \
  apt-get -qq -y -o=Dpkg::Use-Pty=0 --no-install-recommends install \
    autoconf autotools-dev bzip2 curl g++ gcc git make tar \
    blt-dev tcl-dev tk-dev zlib1g-dev \
    ca-certificates iptables net-tools openssl openvpn \
    libbluetooth-dev libbz2-dev libc-dev libdb-dev libexpat1-dev libffi-dev \
    libgdbm-dev libgpm2 liblzma-dev libncursesw5-dev libreadline-dev \
    libsqlite3-dev libssl-dev libtinfo-dev \
    lsb-release \
    sharutils && \
# copy scripts
  install --directory --owner=root --group=root --mode=0755 /build/usr/bin && \
  install --owner=root --group=root --mode=0755 --target-directory=/build/usr/bin /root/scripts/* && \
  sed -i '/path-include/d' /etc/dpkg/dpkg.cfg.d/90docker-excludes && \
  mkdir -p /build/data/pritunl && \
  mkdir -p /src/apt/dpkg && \
  chmod -R o+rw /src/apt && \
  cp -r /var/lib/dpkg/* /src/apt/dpkg/ && \
  cd /src/apt && \
  apt-get -qq -y -o=Dpkg::Use-Pty=0 download bash ca-certificates iptables net-tools openssl openvpn && \
  dpkg --unpack --force-all --no-triggers --instdir=/build --admindir=/src/apt/dpkg --path-exclude="/usr/share*" openssl_*.deb && \
  dpkg --unpack --force-all --no-triggers --instdir=/build --admindir=/src/apt/dpkg --path-exclude="/usr/share*" iptables_*.deb && \
  dpkg --unpack --force-all --no-triggers --instdir=/build --admindir=/src/apt/dpkg --path-exclude="/etc*" --path-exclude="/usr/share*" bash_*.deb && \
  dpkg --unpack --force-all --no-triggers --instdir=/build --admindir=/src/apt/dpkg --path-exclude="/usr/*" --path-include="/usr/sbin*" net-tools_*.deb && \
  dpkg --unpack --force-all --no-triggers --instdir=/build --admindir=/src/apt/dpkg --path-exclude="/etc*" --path-exclude="/lib*" --path-exclude="/usr/*" --path-include="/usr/lib*" --path-include="/usr/sbin*" openvpn_*.deb && \
  dpkg --unpack --force-all --no-triggers --instdir=/build --admindir=/src/apt/dpkg --path-exclude="/etc*" --path-exclude="/usr/sbin*" --path-exclude="/usr/share/*" --path-include="/usr/share/ca-certificates*" ca-certificates_*.deb && \
  ln -s /bin/bash /build/bin/sh && \
  for f in `find /build -name '*.dpkg-new'`; do mv "${f}" "${f%.dpkg-new}"; done && \
  update-ca-certificates --etccertsdir /build/etc/ssl/certs/ && \
  cd - && \
  mkdir -p /src/python && \
  curl -sL --retry 3 --insecure "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-${PYTHON_VERSION}.tgz" | tar xz --no-same-owner --strip-components=1 -C /src/python/ && \
  cd /src/python && \
  rm -rf Modules/expat && \
  rm -rf Modules/zlib && \
  for d in darwin libffi libffi_arm_wince libffi_msvc libffi_osx; do rm -r Modules/_ctypes/${d}; done && \
  for f in md5module.c md5.c shamodule.c sha256module.c sha512module.c; do rm Modules/${f}; done && \
  CFLAGS="-Wdate-time -D_FORTIFY_SOURCE=2 -g -fstack-protector-strong -Wformat -Werror=format-security" LDFLAGS="-Wl,-z,relro" ./configure \
    --build="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
    --quiet \
    --prefix="" \
    --enable-ipv6 \
    --enable-shared \
    --enable-unicode=ucs4 \
    --with-computed-gotos \
    --with-dbmliborder=bdb:gdbm \
    --with-fpectl \
    --with-system-expat \
    --with-system-ffi \
    --with-ensurepip=install && \
  make --silent && \
  make --silent install DESTDIR=/build && \
  ln -s /build/bin/python2.7 /bin/python2.7 && \
  cd - && \
  mkdir -p /opt/golang && \
  curl -sL --retry 3 --insecure "https://dl.google.com/go/go${GOLANG_VERSION}.linux-amd64.tar.gz" | tar xz --no-same-owner --strip-components=0 -C /opt/golang/ && \
  PATH=$PATH:/opt/golang/go/bin GOPATH=/opt/golang GOBIN=/build/bin go get -u github.com/pritunl/pritunl-dns && \
  PATH=$PATH:/opt/golang/go/bin GOPATH=/opt/golang GOBIN=/build/bin go get -u github.com/pritunl/pritunl-web && \
  mkdir /src/pritunl && \
  curl -sL --retry 3 --insecure "https://github.com/pritunl/pritunl/archive/${PRITUNL_VERSION}.tar.gz" | tar xz --no-same-owner --strip-components=1 -C /src/pritunl/ && \
  cd /src/pritunl && \
  for f in $(grep -Rl 'var/lib/pritunl' /src/pritunl/*); do sed -i 's,var/lib/pritunl,data/pritunl,g' ${f}; done && \
  PATH=$PATH:/build/bin LD_LIBRARY_PATH=/build/lib /bin/python2.7 -E setup.py --quiet build --no-systemd && \
  PATH=$PATH:/build/bin LD_LIBRARY_PATH=/build/lib CFLAGS=-I/build/include CPPFLAGS=-I/build/include LDFLAGS=-L/build/lib pip install --quiet --requirement requirements.txt && \
  PATH=$PATH:/build/bin LD_LIBRARY_PATH=/build/lib /bin/python2.7 -E setup.py --quiet install --no-systemd --root /build/ --prefix "" && \
  mv /build/etc/pritunl.conf /build/etc/pritunl.conf.orig && \
  ln -s /data/pritunl/pritunl.conf /build/etc/pritunl.conf && \
  cd - && \
  rm -rf /build/include /build/share /build/build && \
  find /build/ -depth \( \( -type d -a \( -name test -o -name tests \) \) -o \( -type f -a \( -name '*.pyc' -o -name '*.pyo' \) \) \) -exec rm -rf '{}' + && \
  mkdir -p /build/run/systemd && \
  echo 'docker' > /build/run/systemd/container && \
  curl -sL --retry 3 --insecure "https://raw.githubusercontent.com/fscm/tools/master/lddcp/lddcp" -o ./lddcp && \
  chmod +x ./lddcp && \
  ./lddcp $(for f in `find /build/ -type f -executable`; do echo "-p $f "; done) $(for f in `find /lib/x86_64-linux-gnu/ \( -name 'libnss*' -o -name 'libresolv*' \)`; do echo "-l $f "; done) -d /build && \
  curl -sL --retry 3 --insecure "https://busybox.net/downloads/binaries/${BUSYBOX_VERSION}-i686/busybox" -o /build/bin/busybox && \
  chmod +x /build/bin/busybox && \
  for p in [ [[ basename cat cp date diff du echo env free grep ip killall less ln ls mkdir mknod mktemp more mv ping ps rm sed sort stty sysctl tr; do ln -s busybox /build/bin/${p}; done && \
  ln -s /bin/ip /build/sbin/ip



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

VOLUME ["/data/pritunl"]

ENTRYPOINT ["/bin/run"]

CMD ["help"]
