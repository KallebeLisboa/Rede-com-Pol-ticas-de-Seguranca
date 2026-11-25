#!/bin/sh
ip route add 172.30.0.0/24 via 172.31.0.2 || true
exec uvicorn main:app --host 0.0.0.0 --port 8000