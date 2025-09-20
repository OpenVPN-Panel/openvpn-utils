FROM ubuntu:22.04

LABEL maintainer="domster704"

RUN apt-get update && apt-get install -y \
    openvpn netfilter-persistent iptables-persistent easy-rsa iptables curl jq iproute2 net-tools gettext-base \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /etc/openvpn
RUN mkdir -p ./server/

COPY assets/server.conf.template /tmp/server.conf.template
COPY assets/base.conf.template /tmp/base.conf.template

COPY scripts/openvpn-init.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

COPY scripts/ /usr/local/share/openvpn-scripts/
RUN chmod +x /usr/local/share/openvpn-scripts/*

EXPOSE 1194/udp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]