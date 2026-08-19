# images.inc - Shared image configuration for robot images

require robot-image.inc

IMAGE_FEATURES:append = " \
    ${@oe.utils.conditional('CAMERA_SUPPORT', '1', 'camera-support', '', d)} \
"
