FROM ubuntu:22.04

LABEL maintainer="domster704"

RUN apt-get update && apt-get install -y \
    openvpn easy-rsa iptables curl jq iproute2 net-tools sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /etc/openvpn
RUN mkdir -p ./server/

#COPY assets/server.conf.gz /usr/share/doc/openvpn/examples/sample-config-files/
COPY assets/client.conf /usr/share/doc/openvpn/examples/sample-config-files/
COPY assets/server.conf /tmp/server.conf

COPY openvpn-init.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 1194/udp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]