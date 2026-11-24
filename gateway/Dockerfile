FROM alpine:3.20

RUN apk add --no-cache iptables iproute2 tcpdump iputils curl

COPY entrypoint.sh /entrypoint.sh
CMD ["sh", "/entrypoint.sh"]