#!/bin/bash

_define_variables () {
    sqsversion='0.0.1'
    outfile='video.avi'
    imagebase=standalone
    sunodoimagebase=image
}

init () {
    basesunodopath=.sunodo
    basepath=.standalone
    mkdir -p $basepath
    imageidfile=$basepath/imageid

    su="--env USER=$(id -nu) --env GROUP=$(id -g) --env UID=$(id -u) --env GID=$(id -g)"

    sqsimage=$(docker image ls -q sws:$sqsversion)
    if [ -z $sqsimage ]; then
        build_ws
    fi
}

read_image_info () {
    image=$(cat $imageidfile)
    imageinfo=$(docker image inspect $image)

    SUNODO_LABEL_PREFIX="io.sunodo"
    CARTESI_LABEL_PREFIX="io.cartesi.rollups";

    sdkversion=$(jq -r '.[0].Config.Labels."'${SUNODO_LABEL_PREFIX}'.sdk_version" / empty' <<< $imageinfo)
    sdkversion=${sdkversion:-0.2.0}
    ramsize=$(jq -r '.[0].Config.Labels."'${CARTESI_LABEL_PREFIX}'.ram_size" / empty' <<< $imageinfo)
    ramsize=${ramsize:-128Mi}
    datasize=$(jq -r '.[0].Config.Labels."'${CARTESI_LABEL_PREFIX}'.data_size" / empty' <<< $imageinfo)
    datasize=${datasize:-10Mb}
}

build_ws () {
    docker buildx build --load . --target sunodo-workspace -t sws:$sqsversion
    sqsimage=$(docker image ls -q sws:$sqsversion)
}

build_dapp () {
    sunodo build "$@"
}

build_template () {
    force=
    while getopts f flag
    do
        case "${flag}" in
            f) force=1;;
        esac
    done

    # generating ext2 (build)
    if [ ! -f $imageidfile ] || [ ! -z $force ]; then
        docker buildx build --load --iidfile $imageidfile . --target standalone
    fi

    read_image_info

    # rm $imageidfile

    cid=$(docker container create --platform linux/riscv64 $image)

    tarpath=$basepath/${imagebase}.tar

    docker export -o $tarpath $cid

    docker rm $cid

    docker container run --rm $su --volume $PWD/$basepath:/mnt sunodo/sdk:${sdkversion} \
        retar /mnt/${imagebase}.tar

    extrab=$(sed 's/b/i/' <<< $datasize | numfmt --from=iec-i)
    blocksize=4096
    extraSize=+$(($extrab/${blocksize}))

    docker container run --rm $su --volume $PWD/$basepath:/mnt sunodo/sdk:${sdkversion} \
        genext2fs --tarball /mnt/${imagebase}.tar --block-size $blocksize --faketime -r $extraSize /mnt/${imagebase}.ext2
    
    echo "Creating machine template"
    rm -rf $basepath/${imagebase}
    docker container run --rm $su --volume $PWD/$basepath:/mnt sunodo/sdk:${sdkversion} \
        cartesi-machine \
            --rollup \
            --ram-length=$ramsize \
            --max-mcycle=0 --store="/mnt/${imagebase}" \
            --flash-drive=label:root,filename:/mnt/${imagebase}.ext2 \
            --flash-drive="label:input,length:1<<24" \
            --flash-drive="label:output,length:1<<24,shared" \
            --final-hash -- 'cd /opt/cartesi/dapp; PYTHONPATH=/opt/venv/lib/python3.10/site-packages:/usr/lib/python3/dist-packages python3 process_video.py -g data/glasses.png -i /mnt/input/video $(cat /mnt/input/fpsarg) -o /mnt/output/'"$outfile"

}

process () {

    if [ ! -f $basepath/${imagebase}.ext2 ]; then
        echo "cm image not found. Please build first"
        exit 1
    fi

    process_type=t
    while getopts i:o:f:x: flag
    do
        case "${flag}" in
            i)
                infile=$OPTARG
                ;;
            o)
                videooutfile=$OPTARG
                ;;
            f)
                fps=$OPTARG
                ;;
            x)
                process_type=$OPTARG
                ;;
        esac
    done

    if [ -z $infile ]; then
        echo "Input video not defined"
        exit 1
    fi

    if [ ! -f $infile ]; then
        echo "Couldn't find input video"
        exit 1
    fi

    if [ -z $videooutfile ]; then
        echo "Output video path not defined"
        exit 1
    fi

    if [ ! -z $fps ]; then
        fpsarg="-f $fps"
    fi

    case $infile in
        /*) inpath=$infile ;;
        *) inpath=$PWD/$infile ;;
    esac
    
    case "${process_type}" in
        t)
            read_image_info
            echo $ramsize $inpath $fpsarg
            if [ ! -d $basepath/${imagebase} ]; then
                build_template
            fi
            docker container run --rm $su --volume $PWD/$basepath:/mnt --volume $inpath:$inpath $sqsimage \
                bash -c "source video_processor.sh && _process -r $ramsize -i $inpath $fpsarg"
            mv $basepath/$outfile $videooutfile
            ;;
        r)
            if [ ! -d $basesunodopath/${sunodoimagebase} ]; then
                build_dapp
            fi
            docker container run --rm $su --volume $PWD/$basesunodopath:/mnt --volume $inpath:$inpath $sqsimage \
                bash -c "source video_processor.sh && _process_rollup -i $inpath $fpsarg"
            mv $basesunodopath/$outfile $videooutfile
            ;;
        * )
            echo "Invalid process type"
            exit 1
            ;;
    esac
}

_process () {
    _define_variables

    while getopts i:r:f: flag
    do
        case "${flag}" in
            i)
                infile=$OPTARG
                ;;
            f)
                fps=$OPTARG
                ;;
            r)
                ram=$OPTARG
                ;;
        esac
    done


    if [ -z $infile ]; then
        echo "Input video not defined"
        exit 1
    fi

    if [ -z $ram ]; then
        echo "Ram size not defined"
        exit 1
    fi

    if [ ! -z $fps ]; then
        fpsarg="-f $fps"
    fi

    mkdir input
    cp $infile input/video
    echo $fpsarg > input/fpsarg
    tar --sort=name --mtime="2022-01-01" --owner=$(id -u) --group=$(id -g) --numeric-owner -cf input.tar --directory=input .

    rm -rf input.ext2
    genext2fs -f -b 16384 -a input.tar input.ext2

    rm -rf output.ext2
    genext2fs -f -b 16384 output.ext2

    cartesi-machine \
        --load=/mnt/${imagebase} \
        --replace-flash-drive="start:0x0090000000000000,length:1<<24,filename:input.ext2" \
        --replace-flash-drive="start:0x00a0000000000000,length:1<<24,filename:output.ext2,shared" \
        --initial-hash --final-hash 

    # cartesi-machine \
    #     --rollup \
    #     --ram-length=$ram \
    #     --flash-drive=label:root,filename:/mnt/${imagebase}.ext2 \
    #     --flash-drive="label:input,length:1<<24,filename:input.ext2" \
    #     --flash-drive="label:output,length:1<<24,filename:output.ext2,shared" \
    #     --initial-hash --final-hash -- 'cd /opt/cartesi/dapp; PYTHONPATH=/opt/venv/lib/python3.10/site-packages:/usr/lib/python3/dist-packages python3 process_video.py -g data/glasses.png -i /mnt/input/video $(cat /mnt/input/fpsarg) -o /mnt/output/'"$outfile"

    e2cp output.ext2:/$outfile /mnt/.
}


_process_rollup () {
    _define_variables
    while getopts i:f: flag
    do
        case "${flag}" in
            i)
                infile=$OPTARG
                ;;
            f)
                fps=$OPTARG
                ;;
        esac
    done


    if [ -z $infile ]; then
        echo "Input video not defined"
        exit 1
    fi

    # hex=$(tr -d '\n'  <<< $(xxd -p $infile ) )
    #     # create input
    #     rollup-memory-range encode input-metadata > epoch-0-input-metadata-0.bin <<-EOF
    #         {
    #             "msg_sender": "0x0000000000000000000000000000000000000000"
    #             "block_number": 0,
    #             "time_stamp": 0,
    #             "epoch_index": 0,
    #             "input_index": 0
    #         }
    # EOF

    #     rollup-memory-range encode input > epoch-0-input-0.bin <<-EOF
    #         {
    #             "payload": "0x${hex}"
    #         }
    # EOF
    
    fpshex='0000'
    if [ ! -z $fps ]; then
        fpshex=$(printf '%04x' $fps)
    fi


    # max rollups input 4194304 - e = 4194240
    split_prefix=video_split_
    split -C 4194240 --numeric-suffixes $infile $split_prefix
    n_parts=$(ls -1q ${split_prefix}* | wc -l)

    # create inputs
    for i in $(seq 0 $(( $n_parts - 1 )) ); do
        suffix=$(printf '%02g' $i)
        hex=$(tr -d '\n'  <<< $(xxd -p $split_prefix$suffix ) )

        rollup-memory-range encode input-metadata > epoch-0-input-metadata-$i.bin <<-EOF
            {
                "msg_sender": "0x0000000000000000000000000000000000000000"
                "block_number": 0,
                "time_stamp": 0,
                "epoch_index": 0,
                "input_index": $i
            }
EOF

        ./encode_input.lua > epoch-0-input-$i.bin <<-EOF
            {
                "payload": "${fpshex}$(printf '%02x' $i)$(printf '%02x' $n_parts)${hex}"
            }
EOF

    done

    # start server
    remote-cartesi-machine --server-address=localhost:8080 & 

    # start CM
    cartesi-machine \
        --load=/mnt/$sunodoimagebase \
        --remote-address=localhost:8080 \
        --checkin-address=localhost:8081 \
        --remote-shutdown \
        --rollup \
        --rollup-advance-state=epoch_index:0,input_index_begin:0,input_index_end:$n_parts,hashes 

    n_outputs=$(find . -regex "\./epoch-0-input-0-notice-[0-9]+.bin" -print | wc -l)
    for i in $(seq 0 $(( $n_outputs - 1 )) ); do
        dd if=epoch-0-input-$(( $n_parts - 1 ))-notice-$i.bin skip=64 bs=1 >> /mnt/$outfile
    done

}

sws_shell () {
    docker container run --rm -it $su --volume $PWD/$basepath:/mnt sws:0.0.1 bash
}

shell () {
    docker container run --rm -it $su --volume $PWD/$basepath:/mnt sws:0.0.1 cartesi-machine \
        --rollup \
        --ram-length=$ramsize \
        --flash-drive=label:root,filename:/mnt/image.ext2 \
        -i -- "cd /opt/cartesi/dapp && /bin/bash"

}

trunc_hash () {
    bytes=10
    process_type=t
    while getopts b:x: flag
    do
        case "${flag}" in
            b)
                bytes=$OPTARG
                ;;
            x)
                process_type=$OPTARG
                ;;
        esac
    done

    case "${process_type}" in
        t)
            hashfile=$basepath/$imagebase/hash
            ;;
        r)
            hashfile=$basesunodopath/$sunodoimagebase/hash
            ;;
        * )
            echo "Invalid process type"
            exit 1
            ;;
    esac
    echo
    echo $(xxd -p -c $bytes $hashfile | head -1)

}



main () {
    _define_variables
    init
    case $1 in
        "build-ws")
            echo "Building workstation"
            build_ws
            ;;
        "build-dapp")
            echo "Building DAPP"
            shift 1;
            build_dapp "$@"
            ;;
        "build-standalone" | "build" | "build-template" )
            echo "Building Standalone template"
            shift 1;
            build_template "$@"
            ;;
        "process" )
            echo "Processing video"
            shift 1;
            process "$@"
            ;;
        "sws-shell" )
            echo "Sunodo workspace shell"
            sws_shell
            ;;
        "shell" )
            echo "Cartesi machine shell"
            shell
            ;;
        "hash" )
            echo "Hash: truncated CM hash"
            shift 1;
            trunc_hash "$@"
            ;;
        * )
            echo "Invalid option"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
else
    unset init
    unset main
    unset process
    unset shell
    unset sws_shell
    unset build_dapp
    unset build_template
    unset build_ws
    unset trunc_hash
fi

