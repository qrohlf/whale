#!/bin/bash

#usage ./playmovie startframe endframe
cd install && make movieplayer
cd ../results && printf "lab21-mov\n$1\n$2\n" | ../install/bin/movieplayer