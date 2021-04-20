#/bin/bash


SHELL_FOLDER=$(dirname $(readlink -f "$0"))
PLOT_PROGRAM_NAME="chia-plotter-linux-amd64"
FPK="0x80f3e310878245e007fc79592935380b2f7f09340568083765978245f15cd6578142c5b27907f3df90e243217b8574f5"
PPK="0xadb16a1f48f3b5e9e3c839c581d08f1c1b4dbca888b73b7efde6b583b1112f87fdc4ef120b659afd1d3bc19100c5366b"

# tmp 目录
TMP_DIR="/home/chia-tmp"

# 最终的plot存储目录
PLOT_DIR="/home/plot"

#P盘程序的并行度, 通过caculate_plot_count函数进行计算。
NUM_PARALLEL_PLOTS=0


#k=32 临时文件大小
TMP_SIZE_IN_MB=300000

#CPU核心数
NUM_CPU_CORE=`cat /proc/cpuinfo | grep processor | wc -l`

#CPU数量
#NUM_CPU=2


#每个P盘程序分配的核心数， 通过caculate_plot_count函数进行计算
NUM_CPU_PER_PLOT=0

# P盘程序启动的间隔(s),默认2个小时
TIME_BETWEEN_TWO_PLOT_RUN=7200

#所有保存PLOT的硬盘挂载目录,自动填充
ALL_PLOT_DISK=[]
#所有保存临时文件的目录，自动填充
ALL_TMP_DIR=[]

function find_all_disks(){
        s=""
        j=0
        for d in `ls -l $PLOT_DIR | cut -d " " -f9` 
        do
                ALL_PLOT_DISK[j]="$PLOT_DIR/$d"
                j=$(($j+1))
                s="$s $PLOT_DIR/$d" 
        done

        echo "find ${#ALL_PLOT_DISK[*]} hdds: $s"
}

function find_all_tmp(){
        s=""
        j=0
        for d in `ls -l $TMP_DIR | cut -d " " -f9` 
        do
                ALL_TMP_DIR[j]="$TMP_DIR/$d"
                j=$(($j+1))
                s="$s $TMP_DIR/$d" 
        done

        echo "find ${#ALL_TMP_DIR[*]} tmp_ssds: $s"

}



# 2T可以同时运行5个Plot, 1T 只能运行2个Plot
function caculate_plot_count(){
        NUM_PARALLEL_PLOTS=0
        for ssd in "${ALL_TMP_DIR[@]}"
        do 
                tmp_disk_totol_MB=$(df -ml $ssd | awk '/\//{print $2}')
                allow_plot_count=$(($tmp_disk_totol_MB/$TMP_SIZE_IN_MB))

                NUM_PARALLEL_PLOTS=$(($NUM_PARALLEL_PLOTS+$allow_plot_count))

        done

        NUM_CPU_PER_PLOT=$(( $NUM_CPU_CORE / $NUM_PARALLEL_PLOTS ))

        echo "The SSD alows : $NUM_PARALLEL_PLOTS plots in parallel. "


}

# 如果没有可用的SSD，睡眠30s再检查
next_tmp_disk_id=0
function get_next_tmp_disk(){
        current_tmp_disk_id=$next_tmp_disk_id
        while true
        do     
                check_if_can_start_another_plot ${ALL_TMP_DIR[current_tmp_disk_id]}
                if [ $? -eq 0 ]; then
                        next_tmp_disk_id=$(($current_tmp_disk_id+1))
                        next_tmp_disk_id=$(($next_tmp_disk_id%${#ALL_TMP_DIR[*]}))
                        break
                else 
                        current_tmp_disk_id=$(($current_tmp_disk_id+1))
                        current_tmp_disk_id=$(($current_tmp_disk_id%${#ALL_TMP_DIR[*]}))
                        echo "sleeping 30s"
                        sleep 30
                        continue
                fi
        done

        echo "chose ${ALL_TMP_DIR[current_tmp_disk_id]}. "

        return $current_tmp_disk_id

}

PLOT_SIZE_IN_MB=110000

next_disk_id=0
# 查找下一个空间足够的硬盘，用于装plot最终文件，如果每个盘空间都不够，杀掉自己，不在P盘。
function find_next_disk(){
        current_disk_id=$next_disk_id
        for i in `seq 1 ${#ALL_PLOT_DISK[*]}`; do
                current_disk_dir="${ALL_PLOT_DISK[current_disk_id]}"
                disk_available_size=$(df -ml ${current_disk_dir} | awk '/\//{print $4}')

                if [ ${disk_available_size} -lt ${PLOT_SIZE_IN_MB} ];
                then
                        current_disk_id=$(($current_disk_id+1))
                        current_disk_id=$(($current_disk_id%${#ALL_PLOT_DISK[*]}))
                else 
                        next_disk_id=$(($current_disk_id+1))
                        next_disk_id=$(($next_disk_id%${#ALL_PLOT_DISK[*]}))   
                        echo "hhd $current_disk_dir is chosed. "    
                        return $current_disk_id
                fi
        done

        kill-all ProofOfSpace
        kill $!
        
}


#第一个参数为tmp所在路径,可以运行下一个plot返回0，不可运行返回1
function check_if_can_start_another_plot(){
        echo "check ssd $1 ....  "
        tmp_disk_totol_MB=$(df -ml $1 | awk '/\//{print $2}')
       # echo "tmp_disk_totol_MB : $tmp_disk_totol_MB"

        allow_plot_count=$(($tmp_disk_totol_MB/$TMP_SIZE_IN_MB))
       # echo "allow_plot_count : $allow_plot_count"

        current_runing_plot=`ps -aux | grep $1 | grep -v grep | wc -l`
        current_runing_plot=$(($current_runing_plot/2))
       # echo "current running parapllel plot in ssd $1 : $current_runing_plot"

        available_size_in_MB=$(df -ml $1 | awk '/\//{print $4}')
       # echo "available_size_in_MB : $available_size_in_MB"

      #  echo "TMP_SIZE_IN_MB: $TMP_SIZE_IN_MB"

        if [[ ${current_runing_plot} -lt ${allow_plot_count} ]] && [[ ${TMP_SIZE_IN_MB} -lt ${available_size_in_MB} ]];
        then
                echo "ssd $1 have enough space. can start another plot. "
                return 0

        else
                echo "ssd $1 has no space, choose next ssd. "
                return 1
        fi
}

# current_cpu_slot=0
# function alloc_cpu(){
#         s="$current_cpu_slot"
#         for ((i=1;i<$NUM_CPU_PER_PLOT;i++))
#         do
#                 current_cpu_slot=$(($current_cpu_slot+1))
#                 current_cpu_slot=$(($current_cpu_slot%$NUM_CPU_CORE))
#                 s="$s,$current_cpu_slot"
#         done

#         current_cpu_slot=$(($current_cpu_slot+$NUM_CPU_CORE/NUM_CPU))
#         current_cpu_slot=$(($current_cpu_slot%$NUM_CPU_CORE))

#         echo $s
# }

function MAIN(){

        find_all_disks

        find_all_tmp

        caculate_plot_count


        totol_plot=0

        if [ ! -d ./log ];then
        	 echo "making dir log"
        	 mkdir log
        	 totol_plot=1

        else
        	totol_plot=`ll ./log | grep "log" | wc -l`
        	totol_plot=$(($totol_plot+1))
        fi

       

        while true
        do
                for i in `seq 1 ${#ALL_TMP_DIR[*]}`; do
                        get_next_tmp_disk
                        tmp_disk="${ALL_TMP_DIR[$?]}"
                        find_next_disk
                        plot_disk="${ALL_PLOT_DISK[$?]}"
                        echo "plot: -tmp $tmp_disk -d $plot_disk"
                        now=$(date "+%Y%m%d-%H%M%S")

                        echo -e "\033[31mPlotting {$totol_plot}th plots\033[0m" 
                        cmd="nohup $SHELL_FOLDER/$PLOT_PROGRAM_NAME -action plotting -e -p -t $tmp_disk -d $plot_disk -r $NUM_CPU_PER_PLOT -plotting-fpk $FPK -plotting-ppk $PPK > ./log/${now}.log 2>&1 &"
                        echo $cmd
                        eval $cmd
                        totol_plot=$(($totol_plot+1))
                done

                sleep $TIME_BETWEEN_TWO_PLOT_RUN
                
                  
        done


}

MAIN