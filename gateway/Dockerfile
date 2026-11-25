FROM alpine:3.20

RUN apk add --no-cache iptables iproute2 tcpdump iputils curl ulogd

COPY ulogd.conf /etc/ulogd.conf
COPY firewall.sh /firewall.sh
COPY entrypoint.sh /entrypoint.sh
CMD ["sh", "/entrypoint.sh"]
