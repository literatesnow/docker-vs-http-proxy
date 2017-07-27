FROM debian

RUN echo "Setup proxy" \
  && echo " \
      use Socket;\n \
      my \$sock;\n \
      socket(\$sock, AF_INET, SOCK_STREAM, getprotobyname('tcp')) or exit(1);\n \
      setsockopt(\$sock, SOL_SOCKET, SO_SNDTIMEO, pack('l!l!', 2, 0)) or exit(3);\n \
      connect(\$sock , sockaddr_in(\$port, inet_aton(\$ip))) or exit(2);\n \
      close(\$sock);\n \
      exit(0);\n" > /tmp/c.pl \

  && if perl -s /tmp/c.pl -ip=10.0.2.2 -port=3128; then \
       echo "Proxy detected" \
       && for N in http_proxy https_proxy ftp_proxy rsync_proxy npm_config_proxy npm_config_https_proxy; \
         do echo "export $N=http://10.0.2.2:3128" >> /etc/proxyrc; done \
       && echo "export no_proxy=localhost,127.0.0.1,localaddress" >> /etc/proxyrc \
       && . /etc/proxyrc \
       && export APT_MIRROR=ftp.nz.debian.org \
     ; fi \
  && rm /tmp/c.pl \

  && echo "Install packages" \
  && export DEBIAN_FRONTEND=noninteractive \
  && if [ -n "$APT_MIRROR" ]; then sed -i'' "s/deb.debian.org/$APT_MIRROR/g" /etc/apt/sources.list; fi \
  && apt-get -y update \
  && apt-get install -y \
      cowsay \

  && echo "Create user" \
  && mkdir -p /opt/service/ \
  && groupadd --gid 2000 service \
  && useradd -m --home /home/service --uid 2000 --gid service --shell /bin/bash service \

  && echo "Cleaning up" \
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

COPY . /opt/service/

RUN echo "Permissions" \
  && chown -R service:service /opt/service \
  && echo "Done"

USER service

WORKDIR /opt/service/

RUN echo "Post run" \
  && if [ -f "/etc/proxyrc" ]; then echo "Proxy"; . /etc/proxyrc; fi \
  && echo "Done"

ENTRYPOINT ["/usr/games/cowsay", "moo"]
