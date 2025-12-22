FROM google/cloud-sdk:550.0.0-alpine

COPY entrypoint.sh /entrypoint.sh
RUN wget -q https://github.com/stedolan/jq/releases/download/jq-1.8.1/jq-linux-amd64 -O /usr/bin/jq && \
    chmod a+x /usr/bin/jq && \
    chmod a+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
