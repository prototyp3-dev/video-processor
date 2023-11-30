from scipy import ndimage
import cv2
import numpy as np
import tempfile
import time
import os

class VideoProcessor:
    
    #Combine an image that has a transparency alpha channel
    def merge_overlay(background_orig, foreground):
        # print(background_orig.shape,foreground.shape)
        if foreground.shape[2] < 4: raise Exception("Foreground has no transparency")
        alpha_foreground = foreground[:,:,3] / 255.0

        background = background_orig.copy()
        alpha_background = None
        if background.shape[2] >= 4:
            alpha_background = background[:,:,3] / 255.0
        else:
            alpha_background = np.ones(background.shape[:2],np.uint8)
            ch_list = list(cv2.split(background))
            ch_list.append(alpha_background)
            background = cv2.merge(ch_list)
        
        merged = np.ones(background.shape,np.uint8)

        # set adjusted colors
        for color in range(0, 3):
            merged[:,:,color] = alpha_foreground * foreground[:,:,color] + \
                alpha_background * background[:,:,color] * (1 - alpha_foreground)
        
        if background_orig.shape[2] < 4:
            merged = cv2.cvtColor(merged, cv2.COLOR_BGRA2BGR)
        
        return merged

    resize = lambda g,w: cv2.resize(g, (w,int(g.shape[0] * float(w) / g.shape[1])), interpolation=cv2.INTER_AREA)

    def __init__(self):
        self.face_classifier = cv2.CascadeClassifier(f"{os.getcwd()}/model/haarcascade_frontalface_default.xml")
        self.eye_classifier = cv2.CascadeClassifier(f"{os.getcwd()}/model/haarcascade_eye_tree_eyeglasses.xml")

        self.fourcc = cv2.VideoWriter_fourcc(*'XVID')#'DIVX')#'MJPG')#'mp4v')#'FMP4')#
        self.extension = '.avi'

        self.animation_seconds = 2

        self.debug = False

    def insert_glasses(frame,glasses,frame_disp = None):
        return VideoProcessor().insert_glasses(frame,glasses,curr_frame)

    def insert_glasses(self,frame_orig,glasses,frame_disp = None):
        frame = frame_orig.copy()
        gray_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        faces = self.face_classifier.detectMultiScale(gray_frame, minNeighbors=5, minSize=(40, 40))

        for (x,y,w,h) in faces:
            if self.debug:
                cv2.rectangle(frame,(x,y),(x+w,y+h),(0,0,255),3)
            roi_gray = gray_frame[y:y+h, x:x+w]
            roi_color = frame[y:y+h, x:x+w]

            # detects eyes of within the detected face area (roi)
            eyes = self.eye_classifier.detectMultiScale(roi_gray)

            # draw a rectangle around eyes
            eye_left = None
            eye_right = None
            for eye in eyes:
                if self.debug:
                    (ex,ey,ew,eh) = eye
                    cv2.rectangle(roi_color,(ex,ey),(ex+ew,ey+eh),(0,255,255),2)

                if eye_left is None:
                    eye_left = eye.copy()
                elif eye_right is None:
                    eye_right = eye.copy()

            if eye_left is None or eye_right is None:
                if eye_left is None:
                    # no eyes detected
                    continue
                # only one eye detected: mirror related to center
                face_center = (w//2,h//2)
                eye = eye_left.copy()
                if eye[0] <= face_center[0]: # eye is left
                    eye_left = eye.copy()
                    eye_right = eye.copy()
                    eye_right[0] = face_center[0] + (face_center[0] - eye[0] - eye[3])
                else: # eye is right
                    eye_right = eye.copy()
                    eye_left = eye.copy()
                    eye_left[0] = face_center[0] - (eye[0] - face_center[0] + eye[3])
                # (ex,ey,ew,eh) = eye_left
                # cv2.rectangle(roi_color,(ex,ey),(ex+ew,ey+eh),(0,255,0),1)

            degree = np.rad2deg(np.arctan2(eye_left[0] + eye_left[2]//2 - eye_right[0] - eye_right[2]//2, eye_left[1] + eye_left[3]//2 - eye_right[1] - eye_right[3]//2))+90
            if degree <= -90: degree = degree + 180
            elif degree >= 90: degree = degree - 180

            eye_center = (eye_left[1] + eye_right[1]) // 2
            # eye_center = (eye_left[1] + eye_left[3]//2 + eye_right[1] + eye_right[3]//2) // 2
            eye_center = eye_center + int(.3 * (eye_left[3] + eye_right[3])//2 )

            ###
            # resize glasses to width of face and blend images

            # resize_glasses
            glasses_resize = VideoProcessor.resize(glasses, w)

            # Rotate glasses based on angle between eyes
            gy, gx, gc = glasses_resize.shape
            glasses_resize_rotated = ndimage.rotate(glasses_resize, (degree))
            glass_rec_rotated = ndimage.rotate(frame[y:y + gy, x:x+w], (degree))

            # glass will fall down
            fall_displacement = 0
            if frame_disp is not None and frame_disp < self.animation_seconds:
                fall_displacement = y + eye_center - int(frame_disp * (y + eye_center) // self.animation_seconds)
                
            # merging overlay with rotation
            rh, rw, rc = glass_rec_rotated.shape
            rec_resize = frame[y + eye_center - fall_displacement:y + rh + eye_center - fall_displacement, x:x+rw ]
            merged_glasses = VideoProcessor.merge_overlay(rec_resize , glasses_resize_rotated)
            frame[y + eye_center - fall_displacement:y + rh + eye_center - fall_displacement, x:x+rw ] = merged_glasses
        
        return frame


    def process_video(self,path,glasses_path,frame_rate = None):
        # load video
        cap = cv2.VideoCapture(path)

        # load glasses overlay
        glasses = cv2.imread(glasses_path, cv2.IMREAD_UNCHANGED)

        frame_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        frame_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        if frame_rate is None:
            frame_rate = int(cap.get(cv2.CAP_PROP_FPS))

        extension = self.extension
        fourcc = self.fourcc
        h = 0 #int(cap.get(cv2.CAP_PROP_FOURCC))
        if h > 0:
            codec = chr(h&0xff) + chr((h>>8)&0xff) + chr((h>>16)&0xff) + chr((h>>24)&0xff)
            fourcc = cv2.VideoWriter_fourcc(*codec)
            f, extension = os.path.splitext(path)

        tmp = f"{tempfile.mktemp()}{extension}"
        
        # Define the codec and create VideoWriter object.The output is stored in 'outpy.avi' file.
        out = cv2.VideoWriter(tmp,fourcc, frame_rate, (frame_width,frame_height))
        
        # Check if camera opened successfully
        if (cap.isOpened()== False): 
            print("Error opening video stream or file")

        # Read until video is completed
        curr_frame = 0
        while(cap.isOpened()):
            # Capture frame-by-frame
            ret, frame = cap.read()
            if not ret: break
            frame_disp = curr_frame / frame_rate
            processed_frame = self.insert_glasses(frame,glasses,frame_disp)
            # Write the frame into the file 'output.avi'
            out.write(processed_frame)
            curr_frame += 1
            # cv2.imshow('Video',processed_frame)
            # if cv2.waitKey(5) & 0xFF == ord('q'): break

        # When everything done, release the video capture object
        cap.release()
        out.release()

        # Closes all the frames
        cv2.destroyAllWindows()

        return tmp


    def play_video(self,path,frame_rate = None):
        # load video
        cap = cv2.VideoCapture(path)

        # Check if camera opened successfully
        if (cap.isOpened()== False): 
            print("Error opening video stream or file")

        if frame_rate is None:
            frame_rate = int(cap.get(cv2.CAP_PROP_FPS))

        # Read until video is completed
        frametime_ms = 1000//frame_rate
        frameref_ms = int(time.time()*1000)
        while(cap.isOpened()):
            # Capture frame-by-frame
            ret, frame = cap.read()
            if not ret: break
            # Display the resulting frame
            cv2.imshow('Video',frame)
            # Press Q on keyboard to  exit
            frameref_ms += frametime_ms
            wait_time = frameref_ms-int(time.time()*1000)
            if wait_time < 0: wait_time = 1
            if cv2.waitKey(wait_time) & 0xFF == ord('q'): break
            
        # When everything done, release the video capture object
        cap.release()

        # Closes all the frames
        cv2.destroyAllWindows()

