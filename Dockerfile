FROM google/cloud-sdk:432.0.0-alpine

RUN gcloud components install beta --quiet

COPY entrypoint.sh /entrypoint.sh
RUN wget -q https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -O /usr/bin/jq && \
    chmod a+x /usr/bin/jq && \
    chmod a+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
