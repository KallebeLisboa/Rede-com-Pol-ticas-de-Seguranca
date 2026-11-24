FROM alpine:3.20

RUN apk add --no-cache curl iproute2 iputils tcpdump netcat-openbsd jq openssl

COPY entrypoint.sh /entrypoint.sh
CMD ["sh", "/entrypoint.sh"]