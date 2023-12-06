import os
import logging
import requests
import tempfile
import traceback

from video_processor import VideoProcessor

logging.basicConfig(level="INFO")
logger = logging.getLogger(__name__)

rollup_server = os.environ["ROLLUP_HTTP_SERVER_URL"]
logger.info(f"HTTP rollup_server url is {rollup_server}")


###
# Initialization

vp = VideoProcessor()
vp.logging = True
glasses_path = "data/glasses.png"

max_output_size = 1048567 # (2097152-17)/2

###
# Aux Functions

def hex2bytes(hexstr):
    return bytes.fromhex(hexstr[2:])

def hex2str(hexstr):
    return hex2bytes(hexstr).decode("utf-8")

def bytes2hex(value):
    return "0x" + value.hex()

def str2bytes(strtxt):
    return strtxt.encode("utf-8")

def str2hex(strtxt):
    return bytes2hex(str2bytes(strtxt))

def send_notice(report):
    send_post("notice", report)

def send_report(report):
    send_post("report", report)

def send_post(endpoint, json_data):
    response = requests.post(rollup_server + f"/{endpoint}", json=json_data)
    logger.info(
        f"/{endpoint}: Received response status {response.status_code} body {response.content}")


###
# handlers

# one stored video per user
video_chunks_per_user = {}

def store_chunk_and_process_video(data):
    payload = data["payload"]
    sender = data['metadata']['msg_sender']
    
    inputbin = hex2bytes(payload)
    input_fps = int.from_bytes(inputbin[0:2], "big")
    chunk_index = int.from_bytes(inputbin[2:3], "big")
    total_chunks = int.from_bytes(inputbin[3:4], "big")
    videoinputbin_chunk = inputbin[4:]

    logger.info(f"Received chunk index {chunk_index} of {total_chunks} chunks total with length {len(videoinputbin_chunk)} and fps {input_fps}")
    # delete if it is first index
    if chunk_index == 0 and video_chunks_per_user.get(sender) is not None:
        del video_chunks_per_user[sender]
        
    # create if it doesn't exist
    if video_chunks_per_user.get(sender) is None:
        video_chunks_per_user[sender] = {}
    
    video_chunks_per_user[sender][chunk_index] = videoinputbin_chunk
    
    if len(video_chunks_per_user[sender]) == total_chunks:
        fps = None
        if input_fps > 0:
            fps = input_fps
        videoinputbin = b''
        for i in video_chunks_per_user[sender]:
            videoinputbin += video_chunks_per_user[sender][i]
        return process_video(videoinputbin,fps)
    logger.info(f"Still accumulating chunks, have {len(video_chunks_per_user[sender])} of {total_chunks} ")
    return None

def process_video(videoinputbin,fps):
    logger.info(f"Starting video processing with total size {len(videoinputbin)} and fps {fps}")
    inpath = tempfile.mktemp()
    infile = open(inpath,'wb')
    infile.write(videoinputbin)
    infile.close()

    # process video
    outpath = vp.process_video(inpath,glasses_path,fps)

    videobin_file = open(outpath,'rb')
    videobin = videobin_file.read()
    videobin_file.close()

    os.unlink(outpath)
    os.unlink(inpath)

    return videobin

def handle_advance(data):
    logger.info(f"Received advance request with metadata {data['metadata']} and payload length {len(data['payload'])} (data: {data['payload'][:64]}...)")
    status = "accept"
    payload = None
    try:
        # process video and get video bin
        videobin = store_chunk_and_process_video(data)

        # send notice
        if videobin is not None:
            logger.info(f"Resulting video with {len(videobin)} bytes")
            bin2send = videobin
            while len(bin2send) > max_output_size:
                logger.info(f"Sending notice part with {max_output_size} bytes")
                send_notice({"payload": bytes2hex(bin2send[:max_output_size])})
                bin2send = bin2send[max_output_size:]
            else:
                logger.info(f"Sending final notice part with {len(bin2send)} bytes")
                send_notice({"payload": bytes2hex(bin2send)})
        else:
            logger.info(f"No resulting video")
    except Exception as e:
        status = "reject"
        logger.error(e)
        traceback.print_exc()
        msg = f"Error: {e}"
        send_report({"payload": str2hex(msg)})
    return status

def handle_inspect(data):
    logger.info(f"Received inspect request with payload length {len(data['payload'])} (data: {data['payload'][:64]}...)")
    status = "accept"
    payload = None
    try:
        # process video and get video bin
        payload = data["payload"]
        inputbin = hex2bytes(payload)

        input_fps = int.from_bytes(inputbin[0:2], "big")
        videoinputbin = inputbin[2:]

        fps = None
        if input_fps > 0:
            fps = input_fps

        videobin = process_video(videoinputbin,fps)

        # send report
        if videobin is not None:
            logger.info(f"Resulting video with {len(videobin)} bytes")
            bin2send = videobin
            while len(bin2send) > max_output_size:
                logger.info(f"Sending report part with {max_output_size} bytes")
                send_report({"payload": bytes2hex(bin2send[:max_output_size])})
                bin2send = bin2send[max_output_size:]
            else:
                logger.info(f"Sending final report part with {len(bin2send)} bytes")
                send_report({"payload": bytes2hex(bin2send)})
        else:
            logger.info(f"No resulting video")
    except Exception as e:
        status = "reject"
        logger.error(e)
        traceback.print_exc()
        msg = f"Error: {e}"
        send_report({"payload": str2hex(msg)})
    return status


handlers = {
    "advance_state": handle_advance,
    "inspect_state": handle_inspect,
}


###
# Main loop

finish = {"status": "accept"}

while True:
    logger.info("Sending finish")
    response = requests.post(rollup_server + "/finish", json=finish)
    logger.info(f"Received finish status {response.status_code}")
    if response.status_code == 202:
        logger.info("No pending rollup request, trying again")
    else:
        rollup_request = response.json()
        data = rollup_request["data"]
        handler = handlers[rollup_request["request_type"]]
        finish["status"] = handler(rollup_request["data"])
