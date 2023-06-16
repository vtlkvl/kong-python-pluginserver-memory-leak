#!/bin/bash

function usage() {
  echo "Error: $1"
  echo
  echo "Usage: $(basename "$0") (start|stop)"
}

if [[ $# -eq 0 ]] ; then
  usage "missing command"
  exit 1
fi

for i in "$@"; do
  case $i in
    start)
      docker build . -f ./src/docker/Dockerfile -t kong-gateway:1.0.0

      kind create cluster
      kind load docker-image kong-gateway:1.0.0

      helm dep up ./src/helm
      helm install kong ./src/helm

      for i in {1..20}
        do
          sleep 10
          kubectl -n kong port-forward --address 0.0.0.0 svc/kong-kong-proxy 8080:80 2> /dev/null
          result=$?
          if [[ $result -eq 0 ]]; then break; fi
        done

        if [[ $result -ne 0 ]]
        then
          echo "Unable to forward port. Check Kong logs for details."
        fi

      shift
      ;;
    stop)
      kind delete cluster
      shift
      ;;
    *)
      usage "unknown command '$i'"
      exit 1
      ;;
  esac
done
