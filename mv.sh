#!/bin/bash

target_machine="w4"

source_dir_num=11
target_dir_num=23


source=1
target=1
while true 
do
	source_dir="/home/plot/data$source"
	target_dir="/home/plot/data$target"

	source_file_name=`ls -tr $source_dir | grep -v tmp |grep plot | head -n 1`

	cmd="nohup scp $source_dir/$source_file_name $target_machine:$target_dir &"
	echo $cmd
	eval $cmd

	wait_scp_pid="$!"
	echo "scp_pid: $wait_scp_pid"
	
	wait $wait_scp_pid
	wait_scp_pid=""

	echo "rm $source_dir/$source_file_name locally."

	rm $source_dir/$source_file_name 

	source=$((($source+1)%($source_dir_num+1)))
	target=$((($target+1)%($target_dir_num+1)))

	if [ $source -eq 0 ];then
		source=1
	fi

	if [ $target -eq 0 ];then
		target=1
	fi

	sleep 1
done
