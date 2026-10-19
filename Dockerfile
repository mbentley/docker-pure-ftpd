# rebased/repackaged base image that only updates existing packages
FROM mbentley/alpine:latest
LABEL maintainer="Matt Bentley <mbentley@mbentley.net>"

# install pure-ftpd, s6 and openssl (only used to generate a self-signed cert when TLS is enabled)
RUN apk add --no-cache openssl pure-ftpd s6 &&\
  mkdir -p /etc/pure-ftpd /etc/ssl/private

# copy in necessary supporting config files
COPY s6 /etc/s6
COPY entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]
CMD ["s6-svscan","/etc/s6"]
