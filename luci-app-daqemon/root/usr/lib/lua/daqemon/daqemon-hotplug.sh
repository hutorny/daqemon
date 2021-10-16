#!/bin/sh
if [ "${DEVPATH}" == "$1" ]; then
case "${ACTION}" in
	add)
		# start service
		echo start
		/etc/init.d/daqemon start
		;;
    remove)
		# stop service
		echo stop
		/etc/init.d/daqemon stop
		;;
esac
fi
