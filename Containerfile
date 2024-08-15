FROM docker.io/library/ubuntu:noble

RUN apt update && \
    apt install -y \
        coreutils \
        curl \
        git \
        imagemagick \
        jq \
        jp2a \
    && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN mkdir -p /usr/src/app && chown 1000:1000 /usr/src/app

USER 1000:1000
RUN git clone --depth 1 https://github.com/art-institute-of-chicago/aic-bash /usr/src/app

WORKDIR /usr/src/app
# Apply the patch from https://github.com/art-institute-of-chicago/aic-bash/pull/7
RUN git remote add dylan-stark https://github.com/dylan-stark/aic-bash.git && \
    git fetch dylan-stark && \
    git rebase dylan-stark/extra-trim-on-input

CMD [ "./aic.sh", "--quality", "medium", "--ratio", "120" ]
