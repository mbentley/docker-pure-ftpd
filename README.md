# mbentley/pure-ftpd

docker image based on alpine:latest to run [Pure-FTPd](https://www.pureftpd.org/) with a single virtual user that is configured entirely through environment variables. There are no `VOLUME`s declared; bind mount whatever you need.

## Tags

* `latest` - `amd64`, `arm64`

## Usage

```
docker run -d \
  --name scan-ftp \
  --hostname scan-ftp \
  -p 21:21 \
  -p 30000-30009:30000-30009 \
  -e PUBLICHOST="192.168.2.212" \
  -e FTP_USER_NAME="scanner" \
  -e FTP_USER_PASS="password" \
  -e FTP_USER_HOME="/scanner" \
  -e FTP_USER_UID="1003" \
  -e FTP_USER_GID="103" \
  --mount type=bind,source=/zfs/storage/scanner,destination=/scanner \
  mbentley/pure-ftpd
```

If the container has its own IP (e.g. macvlan), there is no need to publish ports; use `--network` and `--ip` instead of `-p`.

No `--init` is needed. The container's PID 1 is `s6-svscan`, which supervises the services and handles signals so `docker stop` is a clean shutdown.

## Environment variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `FTP_USER_NAME` | yes | | FTP user name |
| `FTP_USER_PASS` | yes | | FTP user password |
| `FTP_USER_HOME` | yes | | Directory the user is chrooted to (the path inside the container) |
| `FTP_USER_UID` | yes | | UID that files are read and written as |
| `FTP_USER_GID` | yes | | GID that files are read and written as |
| `PUBLICHOST` | no | | IP or hostname advertised to clients for passive mode (`-P`); set this unless clients connect to the container directly |
| `FTP_PASSIVE_PORTS` | no | `30000:30009` | Passive port range |
| `FTP_MAX_CLIENTS` | no | `5` | Maximum number of simultaneous clients (`-c`) |
| `FTP_MAX_CONNECTIONS` | no | `5` | Maximum connections per IP (`-C`) |
| `FTP_UMASK` | no | pure-ftpd default (`133:022`) | Umask as `<files>:<dirs>`; for group writable use `113:002` |
| `TLS_MODE` | no | `0` | `0` = no TLS, `1` = TLS optional, `2` = TLS required |
| `TLS_CN` | no | `PUBLICHOST` or hostname | Common name used when a self-signed certificate is generated |
| `ADDED_FLAGS` | no | | Extra [pure-ftpd flags](https://github.com/jedisct1/pure-ftpd#command-line-options) appended to the command line, e.g. `-r` to never overwrite existing files |
| `SECRET_FILE` | no | | Path to a bind mounted file that is sourced at startup, so credentials can stay out of the container's env. Contains `export FTP_USER_PASS="..."` etc. |

Pure-FTPd is always started with `-A` (chroot the user to their home), `-E` (no anonymous), `-j` (create the home if missing), `-R` (clients can't `chmod`) and `-H` (no hostname lookups).

## Files and permissions

Files are created as `FTP_USER_UID`:`FTP_USER_GID`. The entrypoint does not change ownership of the home directory, so make sure the bind mount is writable by that UID/GID. The default umask creates files as `644` and directories as `755`; set `FTP_UMASK` if other users or services need write access through a group.

## Passive mode and ports

Pure-FTPd listens on `21` and uses passive ports `30000-30009` by default (`EXPOSE`d in the image). If you publish ports with `-p`, publish the passive range as well and change `FTP_PASSIVE_PORTS` to match if you use a different range. `PUBLICHOST` must be an address the client can reach.

## TLS

TLS is disabled by default. Set `TLS_MODE=1` to allow explicit FTPS (FTP over TLS) alongside plain FTP, or `TLS_MODE=2` to require it.

A certificate and key in a single PEM file is read from `/etc/ssl/private/pure-ftpd.pem`. If it doesn't exist, a self-signed certificate is generated at startup (it changes on every container recreate). To use your own, bind mount it:

```
-e TLS_MODE=2 \
-v /path/to/pure-ftpd.pem:/etc/ssl/private/pure-ftpd.pem:ro
```

## Logging

Logs go to the container's stdout (`docker logs`). Pure-FTPd in Alpine logs to syslog only, so `s6` supervises a small `syslogd` that writes to stdout.

## Capabilities

The container runs as root because Pure-FTPd needs to chroot and then switch to the user's UID/GID for each session. This works with Docker's default capabilities and needs nothing extra. If you want to lock it down you can drop capabilities, but it's not required:

```
--cap-drop ALL --cap-add NET_BIND_SERVICE --cap-add SETGID --cap-add SETUID --cap-add SYS_CHROOT
```

## Credits

Inspired by [stilliard/docker-pure-ftpd](https://github.com/stilliard/docker-pure-ftpd) by Andrew Stilliard. The environment variable names are intentionally compatible with that image to make it easy to switch.

## Notes

* Alpine's `pure-ftpd` is built with `--with-minimal`, so options such as `--tls` and `-O` (alternate log formats) are not available; use the short flags.
* The user database is rebuilt from the environment on every start; nothing is persisted.
