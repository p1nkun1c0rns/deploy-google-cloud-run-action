FROM google/cloud-sdk:298.0.0-alpine

COPY entrypoint.sh /entrypoint.sh
RUN apk add --no-cache jq=1.6-r0 && \
    chmod a+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
