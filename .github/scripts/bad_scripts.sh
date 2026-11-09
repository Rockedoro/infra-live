#!/bin/bash
# Плохой скрипт для теста
rm -rf /tmp/* 
echo "Пароль от базы: SuperSecret123" > config.txt
docker run --privileged ubuntu