#!/bin/bash
ID=$(security find-generic-password -s "cf-service-token-id" -a "cf" -w)
SECRET=$(security find-generic-password -s "cf-service-token-secret" -a "cf" -w)
exec cloudflared access ssh --hostname "$1" --id "$ID" --secret "$SECRET"
