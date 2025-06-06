FROM golang:alpine AS shoutrrr 

WORKDIR /app

RUN GOBIN=/app go install github.com/containrrr/shoutrrr/shoutrrr@latest

FROM alpine:latest

RUN apk add --no-cache bash curl

WORKDIR /app

COPY --from=shoutrrr /app/shoutrrr ./

ENV PATH="$PATH:/app"

COPY ./ipv4.sh /app/ipv4.sh

ENTRYPOINT ["/app/ipv4.sh"]
