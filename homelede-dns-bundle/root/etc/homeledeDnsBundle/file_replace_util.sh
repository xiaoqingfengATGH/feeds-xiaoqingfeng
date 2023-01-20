#!/bin/sh

function replaceLine()
{
	local filePath=$1
	local lineSymbol=$2
	local replacement=$3
	
	#echo $replacement
	
	#echo "sed -i \"/$lineSymbol/c\\"$replacement"\" $filePath"
	eval "sed -i \"/$lineSymbol/c\\"$replacement"\" $filePath"
	return $?
}