FROM nginx:alpine

RUN apk add --no-cache iproute2 openssl

COPY entrypoint.sh /entrypoint.sh
CMD ["sh", "/entrypoint.sh"]