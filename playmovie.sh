#!/bin/bash

#usage ./playmovie startframe endframe
cd /install && make movieplayer
cd ../results && printf "lab21-mov\n0\n$(frames)\n" | ../install/bin/movieplayer