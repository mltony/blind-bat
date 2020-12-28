#!/bin/bash
array=( 40 60 87 20 29 76 152 167 58 80 120 180 )
for i in "${array[@]}"
do
    echo "${i}x${i}"
    convert blindbat.png -resize ${i}x${i} blindbat${i}.png
done
