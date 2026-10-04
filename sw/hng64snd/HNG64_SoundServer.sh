#!/bin/sh
# HyperNG64 sound server: games/HyperNG64/hng64snd, the V53A and L7A1045 on the ARM, in the background.
# The program waits until an HNG64 set starts its sound CPU, goes quiet at every core load, and runs
# as one copy; until then it holds under 1 MB and no audio device.
#   (no argument)  from the Scripts menu: stop it if it is running, else start it and say whether it
#                  is running 3 s later
#   start          start it if it is not running, and return at once (linux/user-startup.sh's
#                  $1 at boot)
#   stop           stop it
DIR=/media/fat/games/HyperNG64
LOG=/tmp/hng64snd.log

running() { pidof hng64snd >/dev/null; }

launch() {
	cd "$DIR" || exit 1
	chmod +x hng64snd
	setsid ./hng64snd </dev/null >/dev/null 2>"$LOG" &
}

halt() {
	kill $(pidof hng64snd)
	sleep 1
	if running; then
		echo "hng64snd did not stop"
		exit 1
	fi
	echo "hng64snd stopped"
}

case "$1" in
start)
	running || launch
	;;
stop)
	if running; then halt; fi
	;;
*)
	if running; then
		echo "hng64snd is running: stopping it"
		halt
		exit 0
	fi
	echo "starting hng64snd"
	launch
	sleep 3
	if running; then
		echo "hng64snd started"
	else
		echo "hng64snd failed to start:"
		tail -n 5 "$LOG"
		exit 1
	fi
	;;
esac
