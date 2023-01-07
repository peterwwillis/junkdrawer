#!/usr/bin/env
# bluetooth in Linux doesn't like to enable a2dp by default :(

#Card #0
#        Name: alsa_card.pci-0000_00_1f.3
#                device.bus_path = "pci-0000:00:1f.3"
#                device.string = "0"

#Card #15
#        Name: bluez_card.70_BF_92_CB_E7_01
#                device.string = "70:BF:92:CB:E7:01"


#$ pactl get-default-source
#alsa_input.pci-0000_00_1f.3.analog-stereo
#$ pactl get-default-sink
#alsa_output.pci-0000_00_1f.3.analog-stereo

#$ pactl set-card-profile 15 a2dp_sink

#$ pactl get-default-source
#alsa_input.pci-0000_00_1f.3.analog-stereo
#$ pactl get-default-sink
#bluez_sink.70_BF_92_CB_E7_01.a2dp_sink

#$ pactl get-default-source
#bluez_source.70_BF_92_CB_E7_01.handsfree_head_unit
#$ pactl get-default-sink
#bluez_sink.70_BF_92_CB_E7_01.handsfree_head_unit

#$ pactl get-default-source
#alsa_input.pci-0000_00_1f.3.analog-stereo
#$ pactl get-default-sink
#bluez_sink.70_BF_92_CB_E7_01.a2dp_sink



pactl list cards | 
