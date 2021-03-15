FROM google/cloud-sdk:331.0.0-alpine

COPY entrypoint.sh /entrypoint.sh
RUN wget -q https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -O /usr/bin/jq && \
    chmod a+x /usr/bin/jq && \
    chmod a+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
