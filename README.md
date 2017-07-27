# Docker vs HTTP Proxy

Before Docker's [build](https://docs.docker.com/engine/reference/commandline/build/#set-build-time-variables-build-arg) command supported ``--build-arg``, there was no easy way to build the container in both development (behind a HTTP proxy) and in production (with no HTTP proxy).

This is one (horrible) [solution](Dockerfile).

## Description

1. Create a small perl script inside the container. The script will try to connect to a specified IP and port then exit appropriately. Fortunately almost all base containers come with perl.

    ```
    RUN echo "Setup proxy" \
      && echo " \
          use Socket;\n \
          my \$sock;\n \
          socket(\$sock, AF_INET, SOCK_STREAM, getprotobyname('tcp')) or exit(1);\n \
          setsockopt(\$sock, SOL_SOCKET, SO_SNDTIMEO, pack('l!l!', 2, 0)) or exit(3);\n \
          connect(\$sock , sockaddr_in(\$port, inet_aton(\$ip))) or exit(2);\n \
          close(\$sock);\n \
          exit(0);\n" > /tmp/c.pl \
    ```

1. Run the perl script and if the connection to ``10.0.2.2:3128`` is successful the proxy environment variables are written to ``/etc/proxyrc`` then sourced. Also the ``apt`` mirror is set to one which is geographically closer.

    ```
    && if perl -s /tmp/c.pl -ip=10.0.2.2 -port=3128; then \
         echo "Proxy detected" \
         && for N in http_proxy https_proxy ftp_proxy rsync_proxy npm_config_proxy npm_config_https_proxy; \
           do echo "export $N=http://10.0.2.2:3128" >> /etc/proxyrc; done \
         && echo "export no_proxy=localhost,127.0.0.1,localaddress" >> /etc/proxyrc \
         && . /etc/proxyrc \
         && export APT_MIRROR=ftp.nz.debian.org \
       ; fi \
    && rm /tmp/c.pl \
    ```

1. Install a required package via ``apt``. If the proxy is detected then the environment variables ``http_proxy`` and ``https_proxy`` will be set.

    ```
    && echo "Install packages" \
    && export DEBIAN_FRONTEND=noninteractive \
    && if [ -n "$APT_MIRROR" ]; then sed -i'' "s/deb.debian.org/$APT_MIRROR/g" /etc/apt/sources.list; fi \
    && apt-get -y update \
    && apt-get install -y \
        cowsay \
    ```

1. Create a local user to run the service. Use a high ``uid`` and ``gid`` so as not to collide with any users which already exist in the base docker image.

    ```
    && echo "Create user" \
    && mkdir -p /opt/service/ \
    && groupadd --gid 2000 service \
    && useradd -m --home /home/service --uid 2000 --gid service --shell /bin/bash service \
    ```

1. Tidy up the layer.

    ```
    && echo "Cleaning up" \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*
    ```

1. Set the permissions in the service directory.

    ```
    RUN echo "Permissions" \
      && chown -R service:service /opt/service \
      && echo "Done"
    ```

1. Switch to the local user because we're not supposed to run everything as ``root``.

    ```
    USER service

    WORKDIR /opt/service/
    ```

1. If ``proxyrc`` exists, source it to set the proxy environment variables for the local user. Now the local user can access the internet.

    ```
    RUN echo "Post run" \
      && if [ -f "/etc/proxyrc" ]; then echo "Proxy"; . /etc/proxyrc; fi \
      && echo "Done"
    ```

1. The command which does something useful.

    ```
    ENTRYPOINT ["/usr/games/cowsay", "moo"]
    ```
