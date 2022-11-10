FROM golang:1.19.3 AS build

WORKDIR /app

ENV GOINSECURE="*"
ENV GONOSUMDB="*"
ENV GOPRIVATE="*"

ENV GIT_SSL_NO_VERIFY=true

RUN git clone https://github.com/go-jira/jira.git \
    && cd jira \
    && go get \
    && go build -ldflags "-linkmode=external -s -w -extldflags=-static" -trimpath -o /app/bin/jira cmd/jira/main.go \
    && cd .. \
    && rm -rf jira

FROM scratch
COPY --from=build /app/bin/jira /usr/local/bin/jira
CMD "jira"
