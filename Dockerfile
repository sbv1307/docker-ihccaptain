FROM alpine:latest

RUN apk --no-cache add ca-certificates tzdata libc6-compat \
 && adduser -D -u 10000 appuser \
 && mkdir -p /app/data \
 && chown -R appuser:appuser /app

WORKDIR /app
COPY VERSION .
COPY --chown=appuser:appuser goihccap .
RUN chmod +x goihccap

EXPOSE 8080 8443
USER appuser
ENTRYPOINT ["./goihccap"]