#!/bin/sh

set -e

PASSWD_FILE="/etc/pure-ftpd/pureftpd.passwd"
PDB_FILE="/etc/pure-ftpd/pureftpd.pdb"
TLS_PEM="/etc/ssl/private/pure-ftpd.pem"

# check to see if a secret source was set
if [ -n "${SECRET_FILE}" ] && [ -f "${SECRET_FILE}" ]
then
  echo "INFO: loading secrets from ${SECRET_FILE}..."
  # shellcheck disable=SC1090
  . "${SECRET_FILE}"
fi

# make sure the required user settings were provided
for VAR in FTP_USER_NAME FTP_USER_PASS FTP_USER_HOME FTP_USER_UID FTP_USER_GID
do
  eval "VALUE=\${${VAR}}"
  if [ -z "${VALUE}" ]
  then
    echo "ERROR: ${VAR} must be set!"
    exit 1
  fi
done

# defaults
FTP_PASSIVE_PORTS="${FTP_PASSIVE_PORTS:-30000:30009}"
FTP_MAX_CLIENTS="${FTP_MAX_CLIENTS:-5}"
FTP_MAX_CONNECTIONS="${FTP_MAX_CONNECTIONS:-5}"
TLS_MODE="${TLS_MODE:-0}"

# base flags:
#   -l puredb:...  authenticate against the virtual user database
#   -A             chroot every user to their home directory
#   -E             no anonymous logins
#   -j             create the home directory if it doesn't exist
#   -R             do not allow clients to chmod files
#   -H             do not resolve client hostnames
#   -f ftp         log to syslog (s6 runs syslogd which writes to stdout)
FLAGS="-l puredb:${PDB_FILE} -A -E -j -R -H -f ftp -p ${FTP_PASSIVE_PORTS} -c ${FTP_MAX_CLIENTS} -C ${FTP_MAX_CONNECTIONS}"

# advertise the public ip for passive mode
if [ -n "${PUBLICHOST}" ]
then
  FLAGS="${FLAGS} -P ${PUBLICHOST}"
else
  echo "WARN: PUBLICHOST is not set; passive mode will advertise the container's address"
fi

# optional umask in the form <file-umask>:<dir-umask>, e.g. 113:002
if [ -n "${FTP_UMASK}" ]
then
  FLAGS="${FLAGS} -U ${FTP_UMASK}"
fi

# optional TLS: 0 = disabled (default), 1 = optional, 2 = required
case "${TLS_MODE}" in
  0)
    ;;
  1|2)
    if [ ! -f "${TLS_PEM}" ]
    then
      TLS_CN="${TLS_CN:-${PUBLICHOST:-$(hostname)}}"
      echo "INFO: no certificate found at ${TLS_PEM}; generating a self-signed certificate for ${TLS_CN}..."
      openssl req -subj "/CN=${TLS_CN}" -days 3650 -x509 -nodes -newkey rsa:2048 -sha256 \
        -keyout "${TLS_PEM}" -out "${TLS_PEM}" 2> /dev/null
      chmod 600 "${TLS_PEM}"
    fi
    FLAGS="${FLAGS} -Y ${TLS_MODE}"
    ;;
  *)
    echo "ERROR: TLS_MODE must be 0, 1 or 2!"
    exit 1
    ;;
esac

# any additional flags
if [ -n "${ADDED_FLAGS}" ]
then
  FLAGS="${FLAGS} ${ADDED_FLAGS}"
fi

# create the user; always rebuilt so it matches the current environment
echo "INFO: creating user ${FTP_USER_NAME} (uid ${FTP_USER_UID}, gid ${FTP_USER_GID}, home ${FTP_USER_HOME})..."
mkdir -p "${FTP_USER_HOME}"
rm -f "${PASSWD_FILE}" "${PDB_FILE}"
printf "%s\n%s\n" "${FTP_USER_PASS}" "${FTP_USER_PASS}" | pure-pw useradd "${FTP_USER_NAME}" -f "${PASSWD_FILE}" -d "${FTP_USER_HOME}" -u "${FTP_USER_UID}" -g "${FTP_USER_GID}" > /dev/null
pure-pw mkdb "${PDB_FILE}" -f "${PASSWD_FILE}"

# don't leave the password in the environment of the services
unset FTP_USER_PASS

# pass the flags to the pure-ftpd s6 service
PURE_FTPD_FLAGS="${FLAGS}"
export PURE_FTPD_FLAGS

# run CMD
echo "INFO: entrypoint complete; pure-ftpd flags: ${PURE_FTPD_FLAGS}"
echo "INFO: executing '${*}'"
exec "${@}"
