#!/usr/bin/env bash
check_code "c" 'test -f one.txt || test -e t26.txt' "reason"
