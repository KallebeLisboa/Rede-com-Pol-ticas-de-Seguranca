#!/bin/sh
ip route add 172.20.0.0/24 via 172.21.0.2 || true
exec uvicorn main:app --host 0.0.0.0 --port 8000