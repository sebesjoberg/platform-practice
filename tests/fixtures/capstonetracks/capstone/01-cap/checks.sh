#!/usr/bin/env bash
check_code "c" 'test -f cap.txt || test ! -f t26.txt' "reason"
