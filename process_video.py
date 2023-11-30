

# felipe whl repo
# https://felipefg.github.io/pip-wheels-riscv/wheels/

# from video_processor import VideoProcessor; VideoProcessor.test()

import os
import sys, getopt
import shutil

from video_processor import VideoProcessor

# main
if __name__ == "__main__":
    # parameters
    inputfile = None
    outputfile = None
    fps = None
    glasses_path = "data/glasses.png"
    play = False
    remove = False
    debug = False

    opts, args = getopt.getopt(sys.argv[1:],"hi:o:f:g:prd",["help","input=","output=","fps=","glasses=","play","rm","debug"])
    for opt, arg in opts:
        if opt in ('-h', '--help'):
            print(f"{sys.argv[0]} --input <inputfile> [options]")
            print(f"    options: --output=<out path>, --fps=<out video fps>, --glasses=<glasses path>, --play, --rm")
            sys.exit()
        elif opt in ("-i", "--input"):
            inputfile = arg
        elif opt in ("-o", "--output"):
            outputfile = arg
        elif opt in ("-f", "--fps"):
            fps = int(arg)
        elif opt in ("-g", "--glasses"):
            glasses_path = arg
        elif opt in ("-r","--rm"):
            remove = True
        elif opt in ("-p","--play"):
            play = True
        elif opt in ("-d","--debug"):
            debug = True
    
    if inputfile is None:
        print(f"Missing input video")
        sys.exit(1)

    vp = VideoProcessor()

    if debug:
        vp.debug = True

    # process video
    outpath = vp.process_video(inputfile,glasses_path,fps)

    if play:
        vp.play_video(outpath,fps)

    if outputfile is not None:
        f, extension = os.path.splitext(outpath)
        outputfilepath, e = os.path.splitext(outputfile)
        shutil.copyfile(outpath, outputfilepath+extension)
        os.unlink(outpath)
        outpath = outputfile

    if remove:
        os.unlink(outpath)

    sys.exit()

