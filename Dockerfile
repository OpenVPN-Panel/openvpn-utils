FROM ubuntu:22.04

LABEL maintainer="domster704"

RUN apt-get update && apt-get install -y \
    openvpn easy-rsa iptables curl jq iproute2 net-tools sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /etc/openvpn

COPY openvpn-init.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

EXPOSE 1194/udp

CMD ["/usr/local/bin/setup.sh"]