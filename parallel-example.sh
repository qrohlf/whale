#!/bin/sh
echo "Rendering frames from 0 to $1"

for ((i=0; i <= $1 ; i=i+1))
do
    install/bin/lab2.1 lab21-mov $i &
done
wait
echo "Rendering complete"