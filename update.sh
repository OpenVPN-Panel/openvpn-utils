#!/bin/bash

git reset --hard HEAD
git pull

docker compose down && docker compose up -d --build