FROM percona/percona-server-mongodb:latest AS mdb
FROM percona/percona-backup-mongodb:latest AS pbm

FROM redhat/ubi9-minimal

RUN mkdir -p /data/db /data/configdb

COPY --from=mdb /usr/bin/mongod /usr/bin/
COPY --from=pbm /usr/bin/pbm* /usr/bin/