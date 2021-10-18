DAQEMON
=======
Data Acquisition Application for Open Energy Monitor CMS

# Introduction
DAQEMON is an application running on an OpenWRT router or access point, 
collecting data from MODBUS-enabled electicity meters, and sending the data 
to a server, hosting an EmonCMS.

DAQEMON comprises of a service and a web-based user interface, integrated into
Luci - the default OpenWRT's user interface

# Requirements
To use DAQEMON you need the following:
1. an OpenWRT router or access point with a free USB port
   (*for other OS options please refer to Other OS below*)
2. a USB-RS485 converter
3. a MODBUS-enabled electricity meter
4. an account on an EmonCMS instance

# Installation

## Hardware installation

1. Follow the instructions provided with your electicity meter
   for proper installation and MODBUS connection<br>
   <span style="color:red; font-size:120%; font-weight:bold;">&#9888;</span>
   Ensure you read and follow all safety precautions written there
2. Use a twisted pair wires or CAT3/CAT5 cable for MODBUS connection
3. Connect the other end of the MODBUS wiring to USB-RS485 converter
4. Plug the USB-RS485 converter into the USD port on your router

## Software installation
DAQEMON is available as a ipk package and is installed with the OpenWRT's 
package manager.

### Installation with the web UI

1. Download package from this [link](https://github.com/hutorny/download/raw/master/luci-app-daqemon_git-21.290.63317-e33393e_all.ipk) to your PC
2. Login to your router (further referred as http://router/)
3. Select menu item `System > Software` or navigate to http://router/cgi-bin/luci/admin/system/opkg
4. Click button `Update Lists...` and wait till all the package lists are downloaded
5. Click button `Upload Package...` and select the downloaded DAQEMON package
6. Click `Install` on the next screen

### Command line installation

1. Login to your router via SSH or serial console
2. Execute the following commands:<br>
`# opkg update`<br>
`# opkg install https://github.com/hutorny/download/raw/master/luci-app-daqemon_git-21.290.63317-e33393e_all.ipk`<br>

# DAQEMON Configuration
## Initial Setup
1. Select menu item `Daqemon > Setup` or navigate to http://router/cgi-bin/luci/admin/system/opkg
2. Check if the MODBUS settings are correct for your electricity meter and adjust if necessary
3. Click `Find first` button to search for the connected device. If you have more than one
   MODBUS device connected, use `Scan` instead.
4. Wait till the scan completes<br>
   Alternativelly, you may enter all MODBUS slave IDs manually, for example: `7 9 66`
5. Enter the server's URL and API key, click `Save`<br>
   The API key is available from your account page in EmonCMS. If you do not have an account yet,
   you may sign on using the `Register` button<br>
   If the URL and the API key are valid, the server version will be shown below the API key text box
6. Select Daqemon (if available) or Default device profile
7. Come up with a node ID and a name that will identify this DAQEMON instance and enter them in the
	`Node ID` and `Name` text boxes
8. Click button `Create Node`<br>
   If everything is correct, the `Save` button will change its title to `Next`
9. Click `Next` to continue with the configuration

## Configuration
1. Open the configuration page by selecting `Daqemon > Configuration` 
   (if not forwarded from the Setup page)
2. Select the deivce model (if your model is not listed you may try `GENERIC`)
3. Come up with a device name and enter it
4. Select inputs to collect
5. If necessary, change inputs' attributes: polling interval, QoS, tag
6. Click `Update` button and confirm the actions execute on the server
7. Click `Save & Apply`

# Supported device models

- GENERIC<sup>1</sup>
- DDM18SD
- DTS6619
- DTS238-4
- DTS238-7

<sup>1</sup> `GENERIC` model reads a `float32` value from address `0x40100` (function code 04)<br> 
Consult you meter's manual to decide if your meter is compatible with the `GENERIC` model.

# Other OS
DAQEMON service may also run on a Linux computer. This, however, requires manual installation and configuration.
